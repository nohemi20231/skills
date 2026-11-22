"""Scan a repository archive stream for skills.

The archive is untrusted input. It is read as a stream and nothing is ever
extracted to disk: only regular files named SKILL.md and the root README are
read, each up to a size limit, and the stream itself is cut at a byte limit.
"""

import tarfile
import zlib
from dataclasses import dataclass, field


@dataclass
class SkillFile:
    path: str
    text: str
    file_count: int = 0
    has_scripts: bool = False


@dataclass
class RepoScan:
    commit: str | None = None
    skills: list[SkillFile] = field(default_factory=list)
    readme: str | None = None
    truncated: bool = False
    error: str | None = None


class _Capped:
    """Reader that serves at most `limit` bytes and notes when more was wanted."""

    def __init__(self, stream, limit: int):
        self._stream = stream
        self._left = limit
        self.hit = False

    def read(self, size: int = -1) -> bytes:
        if self._left <= 0:
            self.hit = True
            return b""
        if size < 0 or size > self._left:
            size = self._left
        data = self._stream.read(size)
        self._left -= len(data)
        return data


def scan(stream, max_bytes: int = 30_000_000, max_file_bytes: int = 262_144) -> RepoScan:
    """Read a .tar.gz of a repository (GitHub layout: one root folder) and return its skills."""
    result = RepoScan()
    capped = _Capped(stream, max_bytes)
    paths = []
    try:
        with tarfile.open(fileobj=capped, mode="r|gz") as archive:
            for member in archive:
                result.commit = archive.pax_headers.get("comment")
                path = member.name.partition("/")[2]
                if not member.isfile() or not path or ".." in path.split("/"):
                    continue
                paths.append(path)
                name = path.rpartition("/")[2]
                if name == "SKILL.md":
                    result.skills.append(SkillFile(path, _text(archive, member, max_file_bytes)))
                elif name == path and name.lower() == "readme.md":
                    result.readme = _text(archive, member, max_file_bytes)
    except (tarfile.TarError, zlib.error, EOFError):
        if not capped.hit:
            result.error = "bad-archive"
    result.truncated = capped.hit
    _count_bundled_files(result.skills, paths)
    return result


def _text(archive, member, limit: int) -> str:
    return archive.extractfile(member).read(limit).decode("utf-8", errors="replace")


def _count_bundled_files(skills: list[SkillFile], paths: list[str]) -> None:
    by_folder = {skill.path.rpartition("/")[0]: skill for skill in skills}
    for path in paths:
        folders = path.split("/")[:-1]
        for depth in range(len(folders) + 1):
            skill = by_folder.get("/".join(folders[:depth]))
            if skill is None or path == skill.path:
                continue
            skill.file_count += 1
            if folders[depth:depth + 1] == ["scripts"]:
                skill.has_scripts = True
