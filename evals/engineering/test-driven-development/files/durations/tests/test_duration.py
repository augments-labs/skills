import unittest

from humanize.duration import describe


class DescribeTest(unittest.TestCase):
    def test_minutes_and_seconds(self):
        self.assertEqual(describe(125), "2 minutes and 5 seconds")

    def test_hours(self):
        self.assertEqual(describe(7200), "2 hours")
