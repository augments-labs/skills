import os
import unittest
from decimal import Decimal
from pathlib import Path

from reports.orders import Order
from reports.summary import render, summarize

from .sample import ORDERS

GOLDEN = Path(__file__).parent / "golden" / "summary.txt"


class SummaryTests(unittest.TestCase):
    def test_summary_matches_golden(self):
        output = render(ORDERS)
        if os.environ.get("UPDATE_GOLDEN"):
            GOLDEN.write_text(output)
        self.assertEqual(output, GOLDEN.read_text())

    def test_counts_orders(self):
        rows = summarize([Order("acme", "EU", Decimal("10")), Order("acme", "EU", Decimal("5"))])
        self.assertEqual(rows, [("acme", "EU", 2, Decimal("15"))])

    def test_empty(self):
        self.assertTrue(render([]).splitlines()[-1].startswith("TOTAL"))


if __name__ == "__main__":
    unittest.main()
