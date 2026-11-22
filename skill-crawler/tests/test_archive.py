import io
import random
import unittest

from skill_crawler.archive import scan
from tests.helpers import SKILL_PDF, make_archive


def scan_bytes(data: bytes, **limits):
    return scan(io.BytesIO(data), **limits)


class ScanArchive(unittest.TestCase):
    def test_returns_each_skill_with_its_repo_relative_path_and_text(self):
        result = scan_bytes(make_archive({
            "skills/pdf/SKILL.md": SKILL_PDF,
            "skills/xlsx/SKILL.md": "---\nname: xlsx\n---\n",
            "docs/SKILLS.md": "not a skill",
        }))
        self.assertEqual(
            [(skill.path, skill.text) for skill in result.skills],
            [("skills/pdf/SKILL.md", SKILL_PDF), ("skills/xlsx/SKILL.md", "---\nname: xlsx\n---\n")],
        )
        self.assertIsNone(result.error)
        self.assertFalse(result.truncated)

    def test_reads_the_commit_from_the_archive_header(self):
        result = scan_bytes(make_archive({"SKILL.md": SKILL_PDF}, commit="e4bb5d9"))
        self.assertEqual(result.commit, "e4bb5d9")

    def test_keeps_the_root_readme_but_not_nested_ones(self):
        root = "see https://github.com/a/b"
        for files in ({"ReadMe.md": root, "docs/README.md": "nested"},
                      {"docs/README.md": "nested", "ReadMe.md": root}):
            with self.subTest(order=list(files)):
                self.assertEqual(scan_bytes(make_archive(files)).readme, root)

    def test_counts_the_files_bundled_with_a_skill_and_flags_scripts(self):
        result = scan_bytes(make_archive({
            "skills/pdf/SKILL.md": SKILL_PDF,
            "skills/pdf/scripts/fill.py": "print()",
            "skills/pdf/reference/forms.md": "forms",
            "skills/plain/SKILL.md": SKILL_PDF,
            "skills/other/notes.txt": "unrelated",
        }))
        self.assertEqual(
            [(skill.path, skill.file_count, skill.has_scripts) for skill in result.skills],
            [("skills/pdf/SKILL.md", 2, True), ("skills/plain/SKILL.md", 0, False)],
        )

    def test_ignores_a_symlink_named_like_a_skill(self):
        result = scan_bytes(make_archive({"a/SKILL.md": SKILL_PDF}, symlinks=["b/SKILL.md"]))
        self.assertEqual([skill.path for skill in result.skills], ["a/SKILL.md"])
        self.assertIsNone(result.error)

    def test_stops_at_the_byte_limit_and_keeps_what_it_read(self):
        noise = random.Random(7).randbytes(400_000)
        data = make_archive({"a/SKILL.md": SKILL_PDF, "big.bin": noise, "z/SKILL.md": SKILL_PDF})
        result = scan_bytes(data, max_bytes=100_000)
        self.assertTrue(result.truncated)
        self.assertEqual([skill.path for skill in result.skills], ["a/SKILL.md"])

    def test_reads_only_the_start_of_an_oversized_skill_file(self):
        result = scan_bytes(make_archive({"a/SKILL.md": "x" * 5000}), max_file_bytes=1000)
        self.assertEqual(result.skills[0].text, "x" * 1000)

    def test_reports_data_that_is_not_an_archive(self):
        result = scan_bytes(b"<html>Not Found</html>")
        self.assertEqual(result.error, "bad-archive")
        self.assertEqual(result.skills, [])


if __name__ == "__main__":
    unittest.main()
