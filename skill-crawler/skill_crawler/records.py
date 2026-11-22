"""Turn a SKILL.md found in a repository into a dataset record."""

import hashlib
import re
from urllib.parse import quote

from .archive import SkillFile
from .frontmatter import parse

# Limits from the Agent Skills specification, https://agentskills.io/specification
_NAME = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")
_NAME_MAX = 64
_DESCRIPTION_MAX = 1024
_COMPATIBILITY_MAX = 500


def check_spec(meta: dict, folder: str) -> list[str]:
    """List the specification rules this frontmatter breaks; `folder` is the skill's directory."""
    problems = []
    name = meta.get("name")
    if name in (None, ""):
        problems.append("missing-name")
    elif not isinstance(name, str) or not _NAME.fullmatch(name):
        problems.append("name-invalid")
    else:
        if len(name) > _NAME_MAX:
            problems.append("name-too-long")
        if name != folder:
            problems.append("name-dir-mismatch")
    description = meta.get("description")
    if description in (None, ""):
        problems.append("missing-description")
    elif not isinstance(description, str):
        problems.append("description-invalid")
    elif len(description) > _DESCRIPTION_MAX:
        problems.append("description-too-long")
    compatibility = meta.get("compatibility")
    if isinstance(compatibility, str) and len(compatibility) > _COMPATIBILITY_MAX:
        problems.append("compatibility-too-long")
    return problems


def skill_record(skill: SkillFile, *, repo, commit, via, depth, repo_meta, fetched_at) -> dict:
    parsed = parse(skill.text)
    meta = parsed.meta or {}
    folder = skill.path.split("/")[-2] if "/" in skill.path else repo.split("/")[1]
    body = parsed.body.strip()
    repo_meta = repo_meta or {}
    return {
        "id": f"{repo}:{skill.path}",
        "repo": repo,
        "path": skill.path,
        "commit": commit,
        "url": f"https://github.com/{repo}/blob/{commit or 'HEAD'}/{quote(skill.path)}",
        "name": _text(meta.get("name")),
        "description": _text(meta.get("description")),
        "license": _text(meta.get("license")),
        "allowed_tools": _tools(meta.get("allowed-tools")),
        "frontmatter_keys": sorted(meta),
        "problems": [parsed.error] if parsed.error else check_spec(meta, folder),
        "body_bytes": len(body.encode()),
        "body_lines": body.count("\n") + 1 if body else 0,
        "body_sha256": hashlib.sha256(body.encode()).hexdigest(),
        "file_count": skill.file_count,
        "has_scripts": skill.has_scripts,
        "via": via,
        "depth": depth,
        "repo_stars": repo_meta.get("stars"),
        "repo_license": repo_meta.get("license"),
        "repo_pushed_at": repo_meta.get("pushed_at"),
        "fetched_at": fetched_at,
    }


def _text(value) -> str | None:
    return value if isinstance(value, str) and value else None


def _tools(value) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    if not isinstance(value, str):
        return []
    parts = value.split(",") if "," in value else value.split()
    return [part.strip() for part in parts if part.strip()]
