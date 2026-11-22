import io
import json
import tempfile
import unittest
from pathlib import Path

from skill_crawler.cli import main
from skill_crawler.fetch import Fetcher
from tests.helpers import SKILL_PDF, FakeWeb, make_archive

ARCHIVE = "https://codeload.github.com/acme/skills/tar.gz/HEAD"


class Cli(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.seeds = self.root / "seeds.txt"
        self.seeds.write_text("# seeds\nhttps://github.com/acme/skills\n")
        self.data = self.root / "data"
        self.web = FakeWeb({ARCHIVE: make_archive({
            "skills/pdf/SKILL.md": SKILL_PDF,
            "skills/xlsx/SKILL.md": "---\nname: xlsx\ndescription: Edit spreadsheets.\n---\n# X\n",
        })})

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        fetcher = Fetcher(self.web, clock=lambda: 0.0, sleep=lambda seconds: None)
        code = main(list(argv), fetcher=fetcher, out=out, err=err)
        return code, out.getvalue(), err.getvalue()

    def crawl(self):
        return self.run_cli("crawl", "--seeds", str(self.seeds), "--out", str(self.data))

    def lines(self, name):
        return [json.loads(line) for line in (self.data / name).read_text().splitlines()]

    def test_crawl_writes_one_json_line_per_skill_and_per_repository(self):
        code, _, _ = self.crawl()
        self.assertEqual(code, 0)
        self.assertEqual([record["id"] for record in self.lines("skills.jsonl")],
                         ["acme/skills:skills/pdf/SKILL.md", "acme/skills:skills/xlsx/SKILL.md"])
        self.assertEqual([(record["repo"], record["skills"]) for record in self.lines("repos.jsonl")],
                         [("acme/skills", 2)])

    def test_crawl_again_replaces_the_previous_snapshot(self):
        self.crawl()
        self.crawl()
        self.assertEqual(len(self.lines("skills.jsonl")), 2)
        self.assertEqual(len(self.lines("repos.jsonl")), 1)

    def test_crawl_honors_the_repository_budget(self):
        self.seeds.write_text("https://github.com/acme/skills\nhttps://github.com/acme/more\n")
        self.run_cli("crawl", "--seeds", str(self.seeds), "--out", str(self.data), "--max-repos", "1")
        self.assertEqual([record["repo"] for record in self.lines("repos.jsonl")], ["acme/skills"])

    def test_crawl_reports_progress_on_stderr_not_stdout(self):
        _, out, err = self.crawl()
        self.assertIn("acme/skills: ok, 2 skills", err)
        self.assertNotIn("acme/skills", out)

    def test_crawl_with_an_unreadable_seed_line_fails_before_any_request(self):
        self.seeds.write_text("not a url\n")
        code, _, err = self.crawl()
        self.assertEqual(code, 2)
        self.assertIn("line 1", err)
        self.assertEqual(self.web.requests, [])
        self.assertFalse((self.data / "skills.jsonl").exists())

    def test_report_summarizes_the_stored_dataset(self):
        self.crawl()
        code, out, _ = self.run_cli("report", "--data", str(self.data))
        self.assertEqual(code, 0)
        self.assertIn("repositories scanned: 1", out)
        self.assertIn("skills: 2", out)
        self.assertIn("acme/skills", out)

    def test_report_without_a_dataset_says_to_crawl_first(self):
        code, _, err = self.run_cli("report", "--data", str(self.data))
        self.assertEqual(code, 2)
        self.assertIn("crawl", err)

    def test_find_prints_the_matching_skill_and_its_link(self):
        self.crawl()
        code, out, _ = self.run_cli("find", "--data", str(self.data), "spreadsheets")
        self.assertEqual(code, 0)
        self.assertIn("https://github.com/acme/skills/blob/c0ffee/skills/xlsx/SKILL.md", out)
        self.assertNotIn("skills/pdf/SKILL.md", out)


if __name__ == "__main__":
    unittest.main()
