import unittest

from skill_crawler.links import extract_repos


class ExtractRepos(unittest.TestCase):
    def test_finds_repos_in_markdown_and_html_links_in_order(self):
        text = (
            "- [superpowers](https://github.com/obra/superpowers) skills\n"
            '<a href="https://github.com/anthropics/skills/tree/main/skills/pdf">pdf</a>\n'
        )
        self.assertEqual(extract_repos(text), ["obra/superpowers", "anthropics/skills"])

    def test_same_repo_in_another_case_is_listed_once_with_first_spelling(self):
        text = "https://github.com/Obra/Superpowers and https://github.com/obra/superpowers/issues"
        self.assertEqual(extract_repos(text), ["Obra/Superpowers"])

    def test_trims_git_suffix_punctuation_fragment_and_query(self):
        cases = {
            "clone https://github.com/a/b.git now": ["a/b"],
            "(see https://github.com/c/d).": ["c/d"],
            "https://github.com/e/f#readme": ["e/f"],
            "https://github.com/g/h?tab=readme-ov-file": ["g/h"],
            "https://github.com/vercel/next.js": ["vercel/next.js"],
        }
        for text, want in cases.items():
            with self.subTest(text=text):
                self.assertEqual(extract_repos(text), want)

    def test_site_pages_and_bare_owners_are_not_repos(self):
        text = (
            "https://github.com/topics/claude-skills "
            "https://github.com/orgs/anthropics/repositories "
            "https://github.com/sponsors/obra "
            "https://github.com/features/copilot "
            "https://github.com/apps/dependabot "
            "https://github.com/obra "
            "https://github.com/obra/"
        )
        self.assertEqual(extract_repos(text), [])

    def test_raw_file_url_maps_to_its_repo(self):
        text = "https://raw.githubusercontent.com/travisvn/awesome-claude-skills/main/README.md"
        self.assertEqual(extract_repos(text), ["travisvn/awesome-claude-skills"])

    def test_lookalike_hosts_are_ignored(self):
        text = (
            "https://notgithub.com/a/b "
            "https://github.com.evil.example/c/d "
            "https://gist.github.com/e/f "
            "https://evil.example/?next=github.com/g/h"
        )
        self.assertEqual(extract_repos(text), [])


if __name__ == "__main__":
    unittest.main()
