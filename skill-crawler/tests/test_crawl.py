import json
import unittest

from skill_crawler.crawl import Seed, crawl, parse_seeds
from skill_crawler.fetch import Fetcher
from tests.helpers import SKILL_PDF, CutOff, FakeWeb, make_archive

SEARCH = "https://api.github.com/search/repositories?q=topic%3Aclaude-skills&sort=stars&order=desc&per_page=100&page="


def archive_url(repo: str) -> str:
    return f"https://codeload.github.com/{repo}/tar.gz/HEAD"


def repo_archive(readme: str = "", skills: tuple = ("pdf",), commit: str = "c0ffee") -> bytes:
    files = {f"skills/{name}/SKILL.md": SKILL_PDF for name in skills}
    if readme:
        files["README.md"] = readme
    return make_archive(files, commit=commit)


def search_reply(*items: dict) -> str:
    return json.dumps({"total_count": len(items), "incomplete_results": False, "items": list(items)})


def search_item(full_name: str, stars: int = 10, spdx: str | None = "MIT") -> dict:
    """One repository as the GitHub search API returns it (fields the API always sends)."""
    owner, name = full_name.split("/")
    return {
        "id": 1, "name": name, "full_name": full_name, "private": False,
        "owner": {"login": owner, "type": "User"},
        "html_url": f"https://github.com/{full_name}", "description": "skills", "fork": False,
        "pushed_at": "2026-11-01T00:00:00Z", "stargazers_count": stars, "archived": False,
        "license": {"key": spdx.lower(), "spdx_id": spdx} if spdx else None,
        "topics": ["claude-skills"], "default_branch": "main",
    }


def run(pages: dict, seeds: list, **options):
    web = FakeWeb(pages)
    fetcher = Fetcher(web, clock=lambda: 0.0, sleep=lambda seconds: None)
    skills, repos = [], []
    crawl(seeds, fetcher, on_skill=skills.append, on_repo=repos.append,
          now=lambda: "2026-11-21T00:00:00Z", **options)
    return skills, repos, web


def scanned(web: FakeWeb) -> list[str]:
    prefix, suffix = "https://codeload.github.com/", "/tar.gz/HEAD"
    return [url[len(prefix):-len(suffix)] for url in web.urls() if url.endswith(suffix)]


class CrawlRepos(unittest.TestCase):
    def test_seed_repo_yields_one_record_per_skill_and_one_for_the_repo(self):
        skills, repos, _ = run(
            {archive_url("acme/skills"): repo_archive(skills=("pdf", "xlsx"), commit="abc123")},
            [Seed("repo", "acme/skills")],
        )
        self.assertEqual(
            [(s["id"], s["commit"], s["depth"], s["via"], s["fetched_at"]) for s in skills],
            [
                ("acme/skills:skills/pdf/SKILL.md", "abc123", 0, "seed", "2026-11-21T00:00:00Z"),
                ("acme/skills:skills/xlsx/SKILL.md", "abc123", 0, "seed", "2026-11-21T00:00:00Z"),
            ],
        )
        self.assertEqual(repos, [{
            "repo": "acme/skills", "status": "ok", "commit": "abc123", "skills": 2,
            "truncated": False, "depth": 0, "via": "seed",
            "stars": None, "license": None, "pushed_at": None,
            "fetched_at": "2026-11-21T00:00:00Z",
        }])

    def test_follows_readme_links_down_to_max_depth_and_no_further(self):
        _, repos, web = run(
            {
                archive_url("list/awesome"): repo_archive(readme="https://github.com/one/level"),
                archive_url("one/level"): repo_archive(readme="https://github.com/two/levels"),
                archive_url("two/levels"): repo_archive(),
            },
            [Seed("repo", "list/awesome")],
            max_depth=1,
        )
        self.assertEqual(scanned(web), ["list/awesome", "one/level"])
        self.assertEqual(
            [(r["repo"], r["depth"], r["via"]) for r in repos],
            [("list/awesome", 0, "seed"), ("one/level", 1, "https://github.com/list/awesome")],
        )

    def test_max_depth_zero_scans_only_the_seeds(self):
        _, _, web = run(
            {archive_url("list/awesome"): repo_archive(readme="https://github.com/one/level")},
            [Seed("repo", "list/awesome")],
            max_depth=0,
        )
        self.assertEqual(scanned(web), ["list/awesome"])

    def test_repo_reached_twice_is_scanned_once(self):
        _, _, web = run(
            {
                archive_url("list/a"): repo_archive(readme="https://github.com/acme/skills"),
                archive_url("list/b"): repo_archive(readme="https://github.com/Acme/Skills"),
                archive_url("acme/skills"): repo_archive(),
            },
            [Seed("repo", "list/a"), Seed("repo", "list/b"), Seed("repo", "list/a")],
        )
        self.assertEqual(scanned(web), ["list/a", "list/b", "acme/skills"])

    def test_stops_scanning_at_the_repo_budget(self):
        links = " ".join(f"https://github.com/acme/r{n}" for n in range(5))
        _, repos, web = run(
            {archive_url("list/awesome"): repo_archive(readme=links)},
            [Seed("repo", "list/awesome")],
            max_repos=3,
        )
        self.assertEqual(scanned(web), ["list/awesome", "acme/r0", "acme/r1"])
        self.assertEqual(len(repos), 3)

    def test_missing_repo_is_recorded_and_the_crawl_goes_on(self):
        skills, repos, _ = run(
            {archive_url("acme/skills"): repo_archive()},
            [Seed("repo", "gone/repo"), Seed("repo", "acme/skills")],
        )
        self.assertEqual([(r["repo"], r["status"], r["skills"]) for r in repos],
                         [("gone/repo", "http-404", 0), ("acme/skills", "ok", 1)])
        self.assertEqual(len(skills), 1)

    def test_network_failure_is_recorded_and_the_crawl_goes_on(self):
        _, repos, _ = run(
            {
                archive_url("down/repo"): ConnectionResetError("reset"),
                archive_url("acme/skills"): repo_archive(),
            },
            [Seed("repo", "down/repo"), Seed("repo", "acme/skills")],
        )
        self.assertEqual([(r["repo"], r["status"]) for r in repos],
                         [("down/repo", "error"), ("acme/skills", "ok")])

    def test_download_that_breaks_midway_is_an_error_with_no_partial_skills(self):
        import random
        files = {"a/SKILL.md": SKILL_PDF, "big.bin": random.Random(7).randbytes(200_000)}
        skills, repos, _ = run(
            {
                archive_url("flaky/repo"): CutOff(make_archive(files), after=50_000),
                archive_url("acme/skills"): repo_archive(),
            },
            [Seed("repo", "flaky/repo"), Seed("repo", "acme/skills")],
        )
        self.assertEqual([(r["repo"], r["status"], r["skills"]) for r in repos],
                         [("flaky/repo", "error", 0), ("acme/skills", "ok", 1)])
        self.assertEqual([s["repo"] for s in skills], ["acme/skills"])

    def test_network_failure_logs_its_cause(self):
        lines = []
        web = FakeWeb({archive_url("down/repo"): ConnectionResetError("connection reset by peer")})
        fetcher = Fetcher(web, clock=lambda: 0.0, sleep=lambda seconds: None)
        crawl([Seed("repo", "down/repo")], fetcher, on_skill=lambda record: None,
              on_repo=lambda record: None, log=lines.append)
        self.assertEqual(lines, ["down/repo: connection reset by peer",
                                 "[1] down/repo: error, 0 skills"])

    def test_reply_that_is_not_an_archive_is_recorded(self):
        _, repos, _ = run({archive_url("odd/repo"): "<html>hello</html>"}, [Seed("repo", "odd/repo")])
        self.assertEqual([(r["repo"], r["status"]) for r in repos], [("odd/repo", "bad-archive")])

    def test_archive_cut_at_the_byte_limit_is_marked_truncated(self):
        import random
        files = {"a/SKILL.md": SKILL_PDF, "big.bin": random.Random(7).randbytes(400_000)}
        skills, repos, _ = run(
            {archive_url("big/repo"): make_archive(files)},
            [Seed("repo", "big/repo")],
            max_archive_bytes=100_000,
        )
        self.assertEqual([(r["status"], r["truncated"], r["skills"]) for r in repos], [("ok", True, 1)])
        self.assertEqual(len(skills), 1)


class CrawlDiscovery(unittest.TestCase):
    def test_search_results_are_scanned_and_carry_repo_metadata(self):
        skills, repos, _ = run(
            {
                SEARCH + "1": search_reply(search_item("acme/skills", stars=42, spdx="Apache-2.0")),
                archive_url("acme/skills"): repo_archive(),
            },
            [Seed("search", "topic:claude-skills")],
        )
        self.assertEqual(
            [(s["repo_stars"], s["repo_license"], s["repo_pushed_at"], s["via"], s["depth"]) for s in skills],
            [(42, "Apache-2.0", "2026-11-01T00:00:00Z", "search:topic:claude-skills", 1)],
        )
        self.assertEqual(
            [(r["stars"], r["license"], r["pushed_at"]) for r in repos],
            [(42, "Apache-2.0", "2026-11-01T00:00:00Z")],
        )

    def test_search_metadata_reaches_a_repo_first_found_another_way(self):
        _, repos, _ = run(
            {
                SEARCH + "1": search_reply(search_item("Acme/Skills", stars=7, spdx=None)),
                archive_url("acme/skills"): repo_archive(),
            },
            [Seed("repo", "acme/skills"), Seed("search", "topic:claude-skills")],
        )
        self.assertEqual([(r["repo"], r["stars"], r["license"]) for r in repos], [("acme/skills", 7, None)])

    def test_search_asks_for_the_next_page_only_after_a_full_one(self):
        full_page = search_reply(*(search_item(f"acme/r{n}") for n in range(100)))
        _, _, web = run(
            {SEARCH + "1": full_page, SEARCH + "2": search_reply(search_item("acme/last")),
             SEARCH + "3": search_reply(search_item("acme/never"))},
            [Seed("search", "topic:claude-skills")],
            search_pages=3, max_repos=0,
        )
        self.assertEqual([url for url in web.urls() if "/search/" in url], [SEARCH + "1", SEARCH + "2"])

    def test_search_stops_at_the_page_limit(self):
        full_page = search_reply(*(search_item(f"acme/r{n}") for n in range(100)))
        _, _, web = run(
            {SEARCH + "1": full_page, SEARCH + "2": full_page},
            [Seed("search", "topic:claude-skills")],
            search_pages=1, max_repos=0,
        )
        self.assertEqual([url for url in web.urls() if "/search/" in url], [SEARCH + "1"])

    def test_refused_search_does_not_stop_the_other_seeds(self):
        _, repos, _ = run(
            {SEARCH + "1": (403, '{"message": "API rate limit exceeded"}'),
             archive_url("acme/skills"): repo_archive()},
            [Seed("search", "topic:claude-skills"), Seed("repo", "acme/skills")],
        )
        self.assertEqual([(r["repo"], r["status"]) for r in repos], [("acme/skills", "ok")])

    def test_search_reply_that_is_not_json_does_not_stop_the_other_seeds(self):
        _, repos, _ = run(
            {SEARCH + "1": "<html>oops</html>", archive_url("acme/skills"): repo_archive()},
            [Seed("search", "topic:claude-skills"), Seed("repo", "acme/skills")],
        )
        self.assertEqual([(r["repo"], r["status"]) for r in repos], [("acme/skills", "ok")])

    def test_repos_linked_from_a_page_are_scanned(self):
        _, repos, _ = run(
            {
                "https://example.org/skills": '<a href="https://github.com/acme/skills">acme</a>',
                archive_url("acme/skills"): repo_archive(),
            },
            [Seed("page", "https://example.org/skills")],
        )
        self.assertEqual([(r["repo"], r["depth"], r["via"]) for r in repos],
                         [("acme/skills", 1, "https://example.org/skills")])

    def test_page_closed_to_robots_is_skipped_and_the_crawl_goes_on(self):
        _, repos, web = run(
            {
                "https://example.org/robots.txt": "User-agent: *\nDisallow: /\n",
                "https://example.org/skills": "https://github.com/hidden/repo",
                archive_url("acme/skills"): repo_archive(),
            },
            [Seed("page", "https://example.org/skills"), Seed("repo", "acme/skills")],
        )
        self.assertNotIn("https://example.org/skills", web.urls())
        self.assertEqual([r["repo"] for r in repos], ["acme/skills"])

    def test_unreachable_page_is_skipped_and_the_crawl_goes_on(self):
        _, repos, _ = run(
            {"https://example.org/robots.txt": TimeoutError("timed out"),
             archive_url("acme/skills"): repo_archive()},
            [Seed("page", "https://example.org/skills"), Seed("repo", "acme/skills")],
        )
        self.assertEqual([r["repo"] for r in repos], ["acme/skills"])

    def test_progress_is_reported_through_the_log(self):
        lines = []
        web = FakeWeb({archive_url("acme/skills"): repo_archive()})
        fetcher = Fetcher(web, clock=lambda: 0.0, sleep=lambda seconds: None)
        crawl([Seed("repo", "acme/skills"), Seed("repo", "gone/repo")], fetcher,
              on_skill=lambda record: None, on_repo=lambda record: None, log=lines.append)
        self.assertEqual(lines, ["[1] acme/skills: ok, 1 skills", "[2] gone/repo: http-404, 0 skills"])


class ParseSeeds(unittest.TestCase):
    def test_classifies_each_kind_of_line(self):
        seeds = parse_seeds([
            "# curated lists",
            "",
            "https://github.com/anthropics/skills",
            "  https://github.com/obra/superpowers/tree/main/skills  ",
            "https://example.org/directory",
            "search:topic:agent-skills",
        ])
        self.assertEqual(seeds, [
            Seed("repo", "anthropics/skills"),
            Seed("repo", "obra/superpowers"),
            Seed("page", "https://example.org/directory"),
            Seed("search", "topic:agent-skills"),
        ])

    def test_rejects_a_line_it_cannot_crawl(self):
        for line in ("ftp://example.org/list", "http://example.org/list", "anthropics/skills", "search:"):
            with self.subTest(line=line):
                with self.assertRaisesRegex(ValueError, "line 2"):
                    parse_seeds(["# header", line])


if __name__ == "__main__":
    unittest.main()
