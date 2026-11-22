import unittest

from skill_crawler.frontmatter import parse


class ParseFrontmatter(unittest.TestCase):
    def test_reads_plain_scalars_and_returns_the_body(self):
        parsed = parse("---\nname: pdf-tools\ndescription: Fill PDF forms.\n---\n# Body\ntext\n")
        self.assertEqual(parsed.meta, {"name": "pdf-tools", "description": "Fill PDF forms."})
        self.assertEqual(parsed.body, "# Body\ntext\n")
        self.assertIsNone(parsed.error)

    def test_unquotes_double_and_single_quoted_values(self):
        parsed = parse(
            "---\n"
            'description: "Use when: the user says \\"ship it\\""\n'
            "license: 'It''s MIT'\n"
            "---\n"
        )
        self.assertEqual(parsed.meta["description"], 'Use when: the user says "ship it"')
        self.assertEqual(parsed.meta["license"], "It's MIT")

    def test_folded_block_joins_lines_with_spaces(self):
        parsed = parse("---\ndescription: >-\n  Fill forms.\n  Use for PDFs.\nname: pdf\n---\n")
        self.assertEqual(parsed.meta, {"description": "Fill forms. Use for PDFs.", "name": "pdf"})

    def test_literal_block_keeps_line_breaks(self):
        parsed = parse("---\ndescription: |\n  Line one\n  Line two\n---\n")
        self.assertEqual(parsed.meta["description"], "Line one\nLine two")

    def test_indented_continuation_extends_a_plain_value(self):
        parsed = parse("---\ndescription: Fill forms.\n  Use for PDFs.\nname: pdf\n---\n")
        self.assertEqual(parsed.meta, {"description": "Fill forms. Use for PDFs.", "name": "pdf"})

    def test_nested_mapping_becomes_a_dict(self):
        parsed = parse('---\nmetadata:\n  author: example-org\n  version: "1.0"\n---\n')
        self.assertEqual(parsed.meta, {"metadata": {"author": "example-org", "version": "1.0"}})

    def test_lists_in_block_unindented_and_flow_form(self):
        cases = {
            "allowed-tools:\n  - Read\n  - Bash\n": ["Read", "Bash"],
            "allowed-tools:\n- Read\n- Bash\n": ["Read", "Bash"],
            'allowed-tools: [Read, "Bash"]\n': ["Read", "Bash"],
        }
        for source, want in cases.items():
            with self.subTest(source=source):
                self.assertEqual(parse("---\n" + source + "---\n").meta, {"allowed-tools": want})

    def test_text_without_frontmatter_is_all_body(self):
        parsed = parse("# Just a heading\n")
        self.assertIsNone(parsed.meta)
        self.assertEqual(parsed.error, "no-frontmatter")
        self.assertEqual(parsed.body, "# Just a heading\n")

    def test_missing_closing_fence_is_reported(self):
        parsed = parse("---\nname: pdf\n# Body\n")
        self.assertIsNone(parsed.meta)
        self.assertEqual(parsed.error, "unterminated-frontmatter")

    def test_unquoted_value_keeps_text_after_a_second_colon(self):
        parsed = parse("---\ndescription: Use when: the user asks\n---\n")
        self.assertEqual(parsed.meta["description"], "Use when: the user asks")

    def test_bom_and_crlf_input_parses_like_plain_input(self):
        parsed = parse(chr(0xFEFF) + "---\r\nname: pdf\r\ndescription: Fill forms.\r\n---\r\nBody\r\n")
        self.assertEqual(parsed.meta, {"name": "pdf", "description": "Fill forms."})
        self.assertEqual(parsed.body, "Body\n")

    def test_comments_are_dropped_outside_quotes_only(self):
        parsed = parse('---\n# a note\nname: pdf # trailing\ndescription: "Issue #12 fixer"\n---\n')
        self.assertEqual(parsed.meta, {"name": "pdf", "description": "Issue #12 fixer"})

    def test_key_without_a_value_is_an_empty_string(self):
        parsed = parse("---\nname:\ndescription: x\n---\n")
        self.assertEqual(parsed.meta, {"name": "", "description": "x"})


if __name__ == "__main__":
    unittest.main()
