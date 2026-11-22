"""Summarize and search a crawled dataset."""

from collections import Counter
from statistics import median

_SPEC_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}


def summarize(skills: list[dict], repos: list[dict]) -> dict:
    repos_per_body = {}
    for skill in skills:
        repos_per_body.setdefault(skill["body_sha256"], set()).add(skill["repo"])
    per_repo = Counter(skill["repo"] for skill in skills)
    stars = {skill["repo"]: skill["repo_stars"] for skill in skills}
    return {
        "repos_scanned": len(repos),
        "repos_with_skills": sum(1 for repo in repos if repo["skills"]),
        "repos_truncated": sum(1 for repo in repos if repo["truncated"]),
        "repo_status": dict(Counter(repo["status"] for repo in repos)),
        "repo_licenses": dict(Counter(repo["license"] or "unknown" for repo in repos if repo["skills"])),
        "skills": len(skills),
        "unique_bodies": len(repos_per_body),
        "skills_copied_across_repos": sum(
            1 for skill in skills if len(repos_per_body[skill["body_sha256"]]) > 1
        ),
        "spec_conforming": sum(1 for skill in skills if not skill["problems"]),
        "problems": _ranked(Counter(p for skill in skills for p in skill["problems"])),
        "with_scripts": sum(1 for skill in skills if skill["has_scripts"]),
        "with_allowed_tools": sum(1 for skill in skills if skill["allowed_tools"]),
        "with_license_field": sum(1 for skill in skills if skill["license"]),
        "extra_frontmatter_keys": _ranked(Counter(
            key for skill in skills for key in skill["frontmatter_keys"] if key not in _SPEC_KEYS
        )),
        "median_body_lines": _median(skill["body_lines"] for skill in skills),
        "median_description_chars": _median(
            len(skill["description"]) for skill in skills if skill["description"]
        ),
        "top_repos": [(repo, count, stars[repo]) for repo, count in _ranked(per_repo).items()][:10],
    }


def find(skills: list[dict], terms: list[str]) -> list[dict]:
    """Skills whose name or description contains every term; starred repositories first."""
    wanted = [term.lower() for term in terms]
    matches = [
        skill for skill in skills
        if all(term in f"{skill['name'] or ''} {skill['description'] or ''}".lower() for term in wanted)
    ]
    return sorted(matches, key=lambda skill: (-(skill["repo_stars"] or 0), skill["id"]))


def _ranked(counts: Counter) -> dict:
    return dict(sorted(counts.items(), key=lambda item: (-item[1], item[0])))


def _median(values) -> int:
    values = list(values)
    return round(median(values)) if values else 0
