import unittest

from cfglint.engine import lint_text


class LintTextTest(unittest.TestCase):
    def test_sorted_by_line(self):
        findings = lint_text("a: 1 \n\tb: 2\n")
        self.assertEqual([(f.line, f.rule) for f in findings],
                         [(1, "trailing-whitespace"), (2, "no-tabs")])

    def test_clean_file(self):
        self.assertEqual(lint_text("a: 1\nb:\n  c: 2\n"), [])
