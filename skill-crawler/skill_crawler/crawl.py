"""The crawl loop: expand seeds into repositories, scan each one for skills.

Seeds are depth 0. Every page and search seed is expanded first, then
repositories are scanned breadth-first in the order they were found, until the
repository budget is spent. A scanned repository's README adds the repositories
it links to, one level deeper, while that stays within `max_depth`.
"""

import json
import re
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import urlencode, urlsplit

from .archive import RepoScan, scan
from .fetch import RobotsDisallowed
from .links import extract_repos
from .records import skill_record

ARCHIVE_URL = "https://codeload.github.com/{repo}/tar.gz/HEAD"
SEARCH_URL = "https://api.github.com/search/repositories?"
_SEARCH_PAGE_SIZE = 100
_SEARCH_MAX_BYTES = 10_000_000
_FULL_NAME = re.compile(r"[A-Za-z0-9-]+/[A-Za-z0-9._-]+")


@dataclass(frozen=True)
class Seed:
    kind: str  # "repo", "page" or "search"
    target: str


def parse_seeds(lines) -> list[Seed]:
    """Read seeds, one per line: a repository URL, any other https page, or `search:<query>`."""
    seeds = []
    for number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        query = line.removeprefix("search:").strip()
        if line.startswith("search:") and query:
            seeds.append(Seed("search", query))
        elif line.startswith("https://"):
            on_github = urlsplit(line).netloc.lower() in ("github.com", "www.github.com")
            repos = extract_repos(line) if on_github else []
            seeds.append(Seed("repo", repos[0]) if repos else Seed("page", line))
        else:
            raise ValueError(
                f"seeds line {number}: expected an https URL or search:<query>, got {line!r}"
            )
    return seeds


def crawl(seeds, fetcher, *, on_skill, on_repo, max_repos=300, max_depth=1, search_pages=1,
          max_archive_bytes=30_000_000, log=lambda line: None, now=None) -> None:
    """Crawl from `seeds`, passing each skill and each scanned repository to the callbacks."""
    run = _Crawl(fetcher, on_skill, on_repo, max_depth, search_pages, max_archive_bytes,
                 log, now or _utc_now)
    for seed in seeds:
        run.expand(seed)
    scanned = 0
    while run.queue and scanned < max_repos:
        scanned += 1
        run.scan(scanned, *run.queue.popleft())


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class _Crawl:
    def __init__(self, fetcher, on_skill, on_repo, max_depth, search_pages, max_archive_bytes,
                 log, now):
        self.fetcher = fetcher
        self.on_skill = on_skill
        self.on_repo = on_repo
        self.max_depth = max_depth
        self.search_pages = search_pages
        self.max_archive_bytes = max_archive_bytes
        self.log = log
        self.now = now
        self.queue = deque()  # (repo, depth, via)
        self.seen = set()  # lower-cased repo names ever queued
        self.repo_meta = {}  # lower-cased repo name -> stars, license, pushed_at

    def expand(self, seed: Seed) -> None:
        if seed.kind == "repo":
            self._add(seed.target, 0, "seed")
        elif seed.kind == "page":
            self._expand_page(seed.target)
        else:
            self._expand_search(seed.target)

    def scan(self, number: int, repo: str, depth: int, via: str) -> None:
        status, result = self._download(repo)
        meta = self.repo_meta.get(repo.lower(), {})
        fetched_at = self.now()
        for skill in result.skills:
            self.on_skill(skill_record(skill, repo=repo, commit=result.commit, via=via,
                                       depth=depth, repo_meta=meta, fetched_at=fetched_at))
        self.on_repo({
            "repo": repo, "status": status, "commit": result.commit,
            "skills": len(result.skills), "truncated": result.truncated,
            "depth": depth, "via": via,
            "stars": meta.get("stars"), "license": meta.get("license"),
            "pushed_at": meta.get("pushed_at"), "fetched_at": fetched_at,
        })
        self.log(f"[{number}] {repo}: {status}, {len(result.skills)} skills")
        for linked in extract_repos(result.readme or ""):
            self._add(linked, depth + 1, f"https://github.com/{repo}")

    def _add(self, repo: str, depth: int, via: str) -> None:
        if depth <= self.max_depth and repo.lower() not in self.seen:
            self.seen.add(repo.lower())
            self.queue.append((repo, depth, via))

    def _download(self, repo: str) -> tuple[str, RepoScan]:
        try:
            reply = self.fetcher.open(ARCHIVE_URL.format(repo=repo))
        except RobotsDisallowed:
            return "robots-disallowed", RepoScan()
        except OSError as error:
            self.log(f"{repo}: {error}")
            return "error", RepoScan()
        try:
            if reply.status != 200:
                return f"http-{reply.status}", RepoScan()
            result = scan(reply, max_bytes=self.max_archive_bytes)
        except OSError as error:
            self.log(f"{repo}: {error}")
            return "error", RepoScan()
        finally:
            reply.close()
        return result.error or "ok", result

    def _expand_page(self, url: str) -> None:
        body = self._get(f"page {url}", url)
        if body is None:
            return
        repos = extract_repos(body.decode("utf-8", errors="replace"))
        self.log(f"page {url}: {len(repos)} repos")
        for repo in repos:
            self._add(repo, 1, url)

    def _expand_search(self, query: str) -> None:
        for page in range(1, self.search_pages + 1):
            label = f"search {query} page {page}"
            body = self._get(label, SEARCH_URL + urlencode({
                "q": query, "sort": "stars", "order": "desc",
                "per_page": _SEARCH_PAGE_SIZE, "page": page,
            }), max_bytes=_SEARCH_MAX_BYTES)
            if body is None:
                return
            try:
                items = [item for item in json.loads(body)["items"]
                         if _FULL_NAME.fullmatch(item["full_name"])]
            except (ValueError, KeyError, TypeError):
                self.log(f"{label}: unreadable reply")
                return
            self.log(f"{label}: {len(items)} repos")
            for item in items:
                self.repo_meta[item["full_name"].lower()] = {
                    "stars": item.get("stargazers_count"),
                    "license": (item.get("license") or {}).get("spdx_id"),
                    "pushed_at": item.get("pushed_at"),
                }
                self._add(item["full_name"], 1, f"search:{query}")
            if len(items) < _SEARCH_PAGE_SIZE:
                return

    def _get(self, label: str, url: str, **limits) -> bytes | None:
        """Fetch a discovery source; log and return None when it cannot be read."""
        try:
            status, body = self.fetcher.get(url, **limits)
        except RobotsDisallowed:
            self.log(f"{label}: robots-disallowed")
            return None
        except OSError as error:
            self.log(f"{label}: error ({error})")
            return None
        if status != 200:
            self.log(f"{label}: http-{status}")
            return None
        return body
