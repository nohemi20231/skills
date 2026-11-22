import unittest

from skill_crawler.archive import SkillFile
from skill_crawler.records import check_spec, skill_record

VALID = {"name": "pdf-tools", "description": "Fill PDF forms."}


class CheckSpec(unittest.TestCase):
    def test_conforming_frontmatter_has_no_problems(self):
        self.assertEqual(check_spec(VALID, "pdf-tools"), [])

    def test_each_rule_of_the_spec_is_reported_by_name(self):
        cases = [
            ({"description": "x"}, "pdf", ["missing-name"]),
            ({"name": "", "description": "x"}, "pdf", ["missing-name"]),
            ({"name": "pdf"}, "pdf", ["missing-description"]),
            ({"name": "PDF-Tools", "description": "x"}, "PDF-Tools", ["name-invalid"]),
            ({"name": "-pdf", "description": "x"}, "-pdf", ["name-invalid"]),
            ({"name": "pdf--tools", "description": "x"}, "pdf--tools", ["name-invalid"]),
            ({"name": "pdf tools", "description": "x"}, "pdf tools", ["name-invalid"]),
            ({"name": ["pdf"], "description": "x"}, "pdf", ["name-invalid"]),
            ({"name": "a" * 65, "description": "x"}, "a" * 65, ["name-too-long"]),
            ({"name": "pdf", "description": "x"}, "pdf-tools", ["name-dir-mismatch"]),
            ({"name": "pdf", "description": "d" * 1025}, "pdf", ["description-too-long"]),
            ({"name": "pdf", "description": ["x"]}, "pdf", ["description-invalid"]),
            ({"name": "pdf", "description": "x", "compatibility": "c" * 501}, "pdf",
             ["compatibility-too-long"]),
        ]
        for meta, folder, want in cases:
            with self.subTest(meta=str(meta)[:60], folder=folder[:20]):
                self.assertEqual(check_spec(meta, folder), want)

    def test_values_at_the_limits_pass(self):
        meta = {"name": "a" * 64, "description": "d" * 1024, "compatibility": "c" * 500}
        self.assertEqual(check_spec(meta, "a" * 64), [])


class SkillRecord(unittest.TestCase):
    def record(self, path="skills/pdf-tools/SKILL.md", text=None, **overrides):
        text = text if text is not None else (
            "---\nname: pdf-tools\ndescription: Fill PDF forms.\nlicense: MIT\n"
            "allowed-tools: Read, Bash\n---\n# PDF\n\nSteps.\n"
        )
        args = dict(
            repo="acme/skills", commit="c0ffee", via="https://example.org/list", depth=1,
            repo_meta={"stars": 42, "license": "Apache-2.0", "pushed_at": "2026-11-01T00:00:00Z"},
            fetched_at="2026-11-21T00:00:00Z",
        )
        args.update(overrides)
        return skill_record(SkillFile(path, text, file_count=3, has_scripts=True), **args)

    def test_carries_identity_frontmatter_and_provenance(self):
        record = self.record()
        want = {
            "id": "acme/skills:skills/pdf-tools/SKILL.md",
            "repo": "acme/skills",
            "path": "skills/pdf-tools/SKILL.md",
            "commit": "c0ffee",
            "url": "https://github.com/acme/skills/blob/c0ffee/skills/pdf-tools/SKILL.md",
            "name": "pdf-tools",
            "description": "Fill PDF forms.",
            "license": "MIT",
            "allowed_tools": ["Read", "Bash"],
            "frontmatter_keys": ["allowed-tools", "description", "license", "name"],
            "problems": [],
            "file_count": 3,
            "has_scripts": True,
            "via": "https://example.org/list",
            "depth": 1,
            "repo_stars": 42,
            "repo_license": "Apache-2.0",
            "repo_pushed_at": "2026-11-01T00:00:00Z",
            "fetched_at": "2026-11-21T00:00:00Z",
        }
        self.assertEqual({key: record[key] for key in want}, want)

    def test_measures_the_body_not_the_frontmatter(self):
        record = self.record()
        self.assertEqual(record["body_lines"], 3)
        self.assertEqual(record["body_bytes"], len("# PDF\n\nSteps."))

    def test_same_body_gives_the_same_hash_despite_frontmatter_and_trailing_space(self):
        first = self.record(text="---\nname: a\ndescription: x\n---\n# Same\n")
        second = self.record(text="---\nname: b\ndescription: y\n---\r\n# Same\n\n\n")
        other = self.record(text="---\nname: a\ndescription: x\n---\n# Different\n")
        self.assertEqual(first["body_sha256"], second["body_sha256"])
        self.assertNotEqual(first["body_sha256"], other["body_sha256"])

    def test_allowed_tools_accepts_the_spec_space_separated_form_and_lists(self):
        cases = {
            "allowed-tools: Read Grep Glob\n": ["Read", "Grep", "Glob"],
            "allowed-tools: Read, Bash(git add:*)\n": ["Read", "Bash(git add:*)"],
            "allowed-tools:\n  - Read\n  - Edit\n": ["Read", "Edit"],
            "": [],
        }
        for line, want in cases.items():
            with self.subTest(line=line):
                record = self.record(text=f"---\nname: pdf-tools\ndescription: x\n{line}---\n")
                self.assertEqual(record["allowed_tools"], want)

    def test_root_skill_is_checked_against_the_repo_name(self):
        text = "---\nname: skills\ndescription: x\n---\n"
        self.assertEqual(self.record(path="SKILL.md", text=text)["problems"], [])
        self.assertEqual(
            self.record(path="SKILL.md", text=text, repo="acme/other")["problems"],
            ["name-dir-mismatch"],
        )

    def test_file_without_frontmatter_is_recorded_with_the_problem(self):
        record = self.record(text="# No frontmatter\n")
        self.assertEqual(record["problems"], ["no-frontmatter"])
        self.assertIsNone(record["name"])
        self.assertIsNone(record["description"])

    def test_unknown_repo_metadata_and_commit_stay_empty(self):
        record = self.record(repo_meta=None, commit=None)
        self.assertEqual(
            (record["repo_stars"], record["repo_license"], record["repo_pushed_at"]),
            (None, None, None),
        )
        self.assertEqual(
            record["url"], "https://github.com/acme/skills/blob/HEAD/skills/pdf-tools/SKILL.md"
        )

    def test_url_escapes_spaces_in_the_path(self):
        record = self.record(path="my skills/pdf-tools/SKILL.md")
        self.assertEqual(
            record["url"], "https://github.com/acme/skills/blob/c0ffee/my%20skills/pdf-tools/SKILL.md"
        )


if __name__ == "__main__":
    unittest.main()
