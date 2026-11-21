import unittest

from cfglint.rules.tabs import NoTabs
from cfglint.rules.whitespace import TrailingWhitespace


class NoTabsTest(unittest.TestCase):
    def test_flags_tab_indent(self):
        findings = NoTabs().check(["a: 1", "\tb: 2"])
        self.assertEqual([f.line for f in findings], [2])

    def test_spaces_are_fine(self):
        self.assertEqual(NoTabs().check(["a:", "  b: 2"]), [])


class TrailingWhitespaceTest(unittest.TestCase):
    def test_flags_trailing_space(self):
        findings = TrailingWhitespace().check(["a: 1 ", "b: 2"])
        self.assertEqual([f.line for f in findings], [1])
