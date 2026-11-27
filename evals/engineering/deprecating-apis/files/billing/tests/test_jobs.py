import unittest

from jobs import dunning


class DunningTest(unittest.TestCase):
    def test_open_invoices(self):
        self.assertEqual(sorted(dunning.run()), ["inv-2", "inv-3"])
