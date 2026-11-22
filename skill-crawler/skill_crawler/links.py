"""Find the GitHub repositories a page or README links to."""

import re

_REPO_URL = re.compile(
    r"https?://(?:www\.)?(?:github\.com|raw\.githubusercontent\.com)"
    r"/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)"
)

# First path segments on github.com that are site pages, not account names.
_SITE_PAGES = frozenset(
    "about apps collections contact copilot customer-stories enterprise events "
    "explore features issues join login marketplace new notifications "
    "open-source orgs pricing pulls readme resources search security settings "
    "signup site solutions sponsors team topics trending user-attachments users".split()
)


def extract_repos(text: str) -> list[str]:
    """Return "owner/repo" for each linked repository, first spelling first."""
    found = {}
    for owner, repo in _REPO_URL.findall(text):
        repo = repo.rstrip(".").removesuffix(".git")
        if owner.lower() in _SITE_PAGES or not repo:
            continue
        found.setdefault(f"{owner}/{repo}".lower(), f"{owner}/{repo}")
    return list(found.values())
