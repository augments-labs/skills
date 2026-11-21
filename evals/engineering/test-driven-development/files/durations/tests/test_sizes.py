import unittest

from humanize.sizes import file_size


class SizesTest(unittest.TestCase):
    def test_sizes(self):
        self.assertEqual(file_size(10), "10 bytes")
        self.assertEqual(file_size(2048), "2.0 KB")
