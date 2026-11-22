"""HTTPS transport that keeps one connection open per host.

Reusing the connection saves a TLS handshake per request, and it avoids asking
the server to close after each reply: some proxies drop the tail of a reply
when the server closes first. A reply that ends before its declared length is
an error here, never a short body.
"""

import base64
import functools
import http.client
import os
import ssl
import urllib.request
from urllib.parse import unquote, urlsplit

_TIMEOUT_SECONDS = 30
_DRAIN_BYTES = 65_536
_SYSTEM_CA_BUNDLE = "/etc/ssl/cert.pem"


class FetchError(OSError):
    """A request could not be completed or its reply cannot be trusted."""


class KeepAliveTransport:
    """Callable `(url, headers) -> reply`; `connect(host, port)` opens a connection."""

    def __init__(self, connect=None):
        self._connect = connect or open_connection
        self._idle = {}  # (host, port) -> connection ready for its next request

    def __call__(self, url: str, headers: dict):
        parts = urlsplit(url)
        origin = (parts.hostname, parts.port)
        target = (parts.path or "/") + (f"?{parts.query}" if parts.query else "")
        reused = self._idle.pop(origin, None)
        if reused is not None:
            try:
                return self._send(reused, origin, target, headers)
            except OSError:
                pass  # the server dropped the idle connection; dial again
        return self._send(self._connect(*origin), origin, target, headers)

    def _send(self, connection, origin, target: str, headers: dict):
        try:
            connection.request("GET", target, headers=headers)
            response = connection.getresponse()
        except (OSError, http.client.HTTPException) as error:
            connection.close()
            raise _as_os_error(error) from error
        return _Reply(response, lambda reusable: self._release(origin, connection, reusable))

    def _release(self, origin, connection, reusable: bool) -> None:
        if reusable:
            self._idle[origin] = connection
        else:
            connection.close()


class _Reply:
    def __init__(self, response, release):
        self.status = response.status
        self.headers = response.headers
        self._response = response
        self._release = release
        self._broken = False
        length = response.headers.get("Content-Length", "")
        self._missing = int(length) if length.isdigit() and not response.chunked else None

    def read(self, size: int = -1) -> bytes:
        try:
            data = self._response.read() if size < 0 else self._response.read(size)
        except (OSError, http.client.HTTPException) as error:
            self._broken = True
            raise _as_os_error(error) from error
        if self._missing is not None:
            self._missing -= len(data)
            if not data and size != 0 and self._missing > 0:
                self._broken = True
                raise FetchError(f"reply ended {self._missing} bytes early")
        return data

    def close(self) -> None:
        """Hand the connection back for reuse if the whole reply was read, else close it."""
        try:
            self.read(_DRAIN_BYTES)
        except OSError:
            pass
        reusable = not self._broken and self._response.isclosed() and not self._response.will_close
        self._response.close()
        self._release(reusable)


def _as_os_error(error: Exception) -> OSError:
    if isinstance(error, OSError):
        return error
    return FetchError(f"{type(error).__name__}: {error}")


def open_connection(host: str, port: int | None) -> http.client.HTTPSConnection:
    """Connect to `host` with certificate checks, through the environment's HTTPS proxy if set."""
    proxy = None if urllib.request.proxy_bypass(host) else urllib.request.getproxies().get("https")
    if not proxy:
        return http.client.HTTPSConnection(host, port, timeout=_TIMEOUT_SECONDS, context=tls_context())
    via = urlsplit(proxy if "://" in proxy else f"http://{proxy}")
    tunnel_headers = {}
    if via.username:
        login = f"{unquote(via.username)}:{unquote(via.password or '')}".encode()
        tunnel_headers["Proxy-Authorization"] = "Basic " + base64.b64encode(login).decode()
    connection = http.client.HTTPSConnection(
        via.hostname, via.port, timeout=_TIMEOUT_SECONDS, context=tls_context()
    )
    connection.set_tunnel(host, port or 443, headers=tunnel_headers)
    return connection


@functools.cache
def tls_context() -> ssl.SSLContext:
    """Default verification; fall back to the OS bundle when this Python has no CA store."""
    context = ssl.create_default_context()
    paths = ssl.get_default_verify_paths()
    if not (paths.cafile or paths.capath) and os.path.exists(_SYSTEM_CA_BUNDLE):
        context.load_verify_locations(_SYSTEM_CA_BUNDLE)
    return context
