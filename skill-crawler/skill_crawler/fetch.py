"""Polite HTTP access: https only, one User-Agent, a delay per host, robots.txt honored.

No credentials are ever sent. `transport` is the only network boundary: a
callable `(url, headers) -> reply` where the reply has `.status`, `.headers`,
`.read(n)` and `.close()`. Network failures surface as OSError.
"""

import time
from urllib.parse import urljoin, urlsplit
from urllib.robotparser import RobotFileParser

from .transport import FetchError, KeepAliveTransport

USER_AGENT = "skill-crawler/0.1 (stdlib http.client)"
_ROBOTS_MAX_BYTES = 500_000
_REDIRECTS = (301, 302, 303, 307, 308)
_MAX_REDIRECTS = 5


class RobotsDisallowed(Exception):
    """The site's robots.txt does not allow this crawler to fetch the URL."""


class Fetcher:
    def __init__(self, transport=None, *, user_agent=USER_AGENT, delay=1.0, host_delays=None,
                 clock=time.monotonic, sleep=time.sleep):
        self._transport = transport or KeepAliveTransport()
        self._user_agent = user_agent
        self._delay = delay
        self._host_delays = host_delays or {}
        self._clock = clock
        self._sleep = sleep
        self._last_request = {}
        self._robots = {}

    def open(self, url: str):
        """Return the reply stream for `url`, after redirects; the caller reads and closes it."""
        if urlsplit(url).scheme != "https" or not urlsplit(url).netloc:
            raise ValueError(f"not an https URL: {url}")
        for _ in range(_MAX_REDIRECTS + 1):
            self._check_robots(url)
            reply = self._request(url)
            location = reply.headers.get("Location")
            if reply.status not in _REDIRECTS or not location:
                return reply
            reply.close()
            url = urljoin(url, location)
            if urlsplit(url).scheme != "https":
                raise FetchError(f"redirect away from https: {url}")
        raise FetchError(f"too many redirects, last to {url}")

    def get(self, url: str, max_bytes: int = 2_000_000) -> tuple[int, bytes]:
        """Fetch a small resource: its status and at most `max_bytes` of body."""
        reply = self.open(url)
        try:
            return reply.status, reply.read(max_bytes)
        finally:
            reply.close()

    def _request(self, url: str):
        host = urlsplit(url).netloc
        last = self._last_request.get(host)
        if last is not None:
            wait = last + self._host_delays.get(host, self._delay) - self._clock()
            if wait > 0:
                self._sleep(wait)
        self._last_request[host] = self._clock()
        return self._transport(url, {"User-Agent": self._user_agent})

    def _check_robots(self, url: str) -> None:
        origin = "https://" + urlsplit(url).netloc
        if origin not in self._robots:
            self._robots[origin] = self._load_robots(origin)
        if not self._robots[origin].can_fetch(self._user_agent, url):
            raise RobotsDisallowed(url)

    def _load_robots(self, origin: str) -> RobotFileParser:
        rules = RobotFileParser()
        reply = self._request(origin + "/robots.txt")
        try:
            status, body = reply.status, reply.read(_ROBOTS_MAX_BYTES)
        finally:
            reply.close()
        if status == 200:
            rules.parse(body.decode("utf-8", errors="replace").splitlines())
        elif status in (401, 403) or status >= 500:
            rules.disallow_all = True
        else:
            rules.allow_all = True
        return rules
