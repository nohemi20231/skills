"""Test fixtures: in-memory repo archives and a canned network."""

import io
import tarfile

SKILL_PDF = "---\nname: pdf\ndescription: Fill PDF forms. Use for PDFs.\n---\n# PDF\n"


def make_archive(files: dict, commit: str = "c0ffee", root: str = "repo-HEAD", symlinks=()) -> bytes:
    """Build a .tar.gz shaped like a GitHub archive: one root folder, commit in the pax header."""
    buffer = io.BytesIO()
    with tarfile.open(
        fileobj=buffer, mode="w:gz", format=tarfile.PAX_FORMAT, pax_headers={"comment": commit}
    ) as archive:
        for path, content in files.items():
            data = content.encode() if isinstance(content, str) else content
            member = tarfile.TarInfo(f"{root}/{path}")
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
        for path in symlinks:
            member = tarfile.TarInfo(f"{root}/{path}")
            member.type = tarfile.SYMTYPE
            member.linkname = "/etc/passwd"
            archive.addfile(member)
    return buffer.getvalue()


class Reply:
    """What a transport returns: a status, headers and a readable body."""

    def __init__(self, status: int, body: bytes = b"", headers: dict | None = None,
                 fails_after: int | None = None):
        self.status = status
        self.headers = headers or {}
        self._body = io.BytesIO(body)
        self._fails_after = fails_after

    def read(self, size: int = -1) -> bytes:
        if self._fails_after is not None and self._body.tell() >= self._fails_after:
            raise ConnectionResetError("connection reset mid-body")
        return self._body.read(size)

    def close(self) -> None:
        pass


def redirect(location: str, status: int = 302) -> tuple:
    return (status, b"", {"Location": location})


class CutOff:
    """A page whose download breaks after `after` bytes."""

    def __init__(self, body: bytes, after: int):
        self.body = body
        self.after = after


class FakeWeb:
    """A transport that serves canned replies and records every request.

    A page is a body (status 200), a `(status, body)` or `(status, body, headers)`
    tuple, an exception to raise on connect, or a `CutOff` download.
    """

    def __init__(self, pages: dict):
        self.pages = pages
        self.requests = []

    def __call__(self, url: str, headers: dict) -> Reply:
        self.requests.append((url, headers))
        page = self.pages.get(url, (404, b""))
        if isinstance(page, Exception):
            raise page
        if isinstance(page, CutOff):
            return Reply(200, page.body, fails_after=page.after)
        status, body, *rest = page if isinstance(page, tuple) else (200, page)
        return Reply(status, body.encode() if isinstance(body, str) else body, *rest)

    def urls(self) -> list[str]:
        return [url for url, _ in self.requests]
