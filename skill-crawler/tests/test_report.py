import unittest

from skill_crawler.report import find, summarize


def skill(repo, name, *, body="h1", problems=(), description="Fill PDF forms.", stars=None,
          keys=("description", "name"), scripts=False, tools=(), license=None, lines=10):
    return {
        "id": f"{repo}:skills/{name}/SKILL.md", "repo": repo, "name": name,
        "url": f"https://github.com/{repo}/blob/c0ffee/skills/{name}/SKILL.md",
        "description": description, "license": license, "allowed_tools": list(tools),
        "frontmatter_keys": list(keys), "problems": list(problems), "body_sha256": body,
        "body_lines": lines, "has_scripts": scripts, "repo_stars": stars,
    }


def repo(name, status="ok", skills=0, truncated=False, stars=None, license=None):
    return {"repo": name, "status": status, "skills": skills, "truncated": truncated,
            "stars": stars, "license": license}


SKILLS = [
    skill("acme/skills", "pdf", body="h1", stars=50, scripts=True, license="MIT", lines=10),
    skill("acme/skills", "xlsx", body="h2", stars=50, tools=("Read",), lines=30,
          keys=("allowed-tools", "description", "name", "version"), description="Edit sheets."),
    skill("fork/skills", "pdf", body="h1", problems=("name-dir-mismatch",), lines=10),
    skill("solo/tool", None, body="h3", problems=("missing-name", "missing-description"),
          description=None, keys=("version", "author"), lines=200),
]
REPOS = [
    repo("acme/skills", skills=2, stars=50, license="MIT"),
    repo("fork/skills", skills=1),
    repo("solo/tool", skills=1, truncated=True, license="MIT"),
    repo("empty/repo"),
    repo("gone/repo", status="http-404"),
]


class Summarize(unittest.TestCase):
    def setUp(self):
        self.summary = summarize(SKILLS, REPOS)

    def test_counts_repositories_by_outcome(self):
        self.assertEqual(self.summary["repos_scanned"], 5)
        self.assertEqual(self.summary["repos_with_skills"], 3)
        self.assertEqual(self.summary["repos_truncated"], 1)
        self.assertEqual(self.summary["repo_status"], {"ok": 4, "http-404": 1})

    def test_counts_skills_and_copies_across_repositories(self):
        self.assertEqual(self.summary["skills"], 4)
        self.assertEqual(self.summary["unique_bodies"], 3)
        self.assertEqual(self.summary["skills_copied_across_repos"], 2)

    def test_same_body_twice_in_one_repository_is_not_a_cross_repo_copy(self):
        skills = [skill("acme/skills", "a", body="same"), skill("acme/skills", "b", body="same")]
        self.assertEqual(summarize(skills, [])["skills_copied_across_repos"], 0)

    def test_tallies_spec_problems_most_frequent_first(self):
        skills = SKILLS + [skill("x/y", "z", body="h9", problems=("name-dir-mismatch",))]
        summary = summarize(skills, REPOS)
        self.assertEqual(
            list(summary["problems"].items()),
            [("name-dir-mismatch", 2), ("missing-description", 1), ("missing-name", 1)],
        )
        self.assertEqual(summary["spec_conforming"], 2)

    def test_counts_skill_traits(self):
        self.assertEqual(self.summary["with_scripts"], 1)
        self.assertEqual(self.summary["with_allowed_tools"], 1)
        self.assertEqual(self.summary["with_license_field"], 1)

    def test_counts_frontmatter_keys_outside_the_spec(self):
        self.assertEqual(self.summary["extra_frontmatter_keys"], {"version": 2, "author": 1})

    def test_reports_medians(self):
        self.assertEqual(self.summary["median_body_lines"], 20)
        self.assertEqual(self.summary["median_description_chars"], 15)  # "Fill PDF forms." x2, "Edit sheets."

    def test_ranks_repositories_by_skill_count(self):
        self.assertEqual(
            self.summary["top_repos"],
            [("acme/skills", 2, 50), ("fork/skills", 1, None), ("solo/tool", 1, None)],
        )

    def test_counts_licenses_of_repositories_that_have_skills(self):
        self.assertEqual(self.summary["repo_licenses"], {"MIT": 2, "unknown": 1})

    def test_empty_dataset_summarizes_to_zeroes(self):
        summary = summarize([], [])
        self.assertEqual((summary["skills"], summary["repos_scanned"]), (0, 0))
        self.assertEqual((summary["median_body_lines"], summary["median_description_chars"]), (0, 0))


class Find(unittest.TestCase):
    def test_matches_all_terms_in_name_or_description_ignoring_case(self):
        self.assertEqual([s["id"] for s in find(SKILLS, ["PDF", "forms"])],
                         ["acme/skills:skills/pdf/SKILL.md", "fork/skills:skills/pdf/SKILL.md"])
        self.assertEqual([s["id"] for s in find(SKILLS, ["xlsx"])], ["acme/skills:skills/xlsx/SKILL.md"])
        self.assertEqual(find(SKILLS, ["pdf", "sheets"]), [])

    def test_puts_skills_from_starred_repositories_first(self):
        skills = [skill("low/a", "pdf", stars=None), skill("mid/b", "pdf", stars=5),
                  skill("top/c", "pdf", stars=900)]
        self.assertEqual([s["repo"] for s in find(skills, ["pdf"])], ["top/c", "mid/b", "low/a"])

    def test_skill_without_name_or_description_is_searchable_without_error(self):
        self.assertEqual(find(SKILLS, ["solo"]), [])


if __name__ == "__main__":
    unittest.main()
