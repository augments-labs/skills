import unittest

from app import pricing, store


class PricingTest(unittest.TestCase):
    def test_total_cents(self):
        self.assertEqual(pricing.total_cents(store.get("inv-1")["lines"]), 3750)

    def test_legacy_total_is_dollars(self):
        self.assertEqual(pricing.legacy_total(store.get("inv-1")["lines"]), 37.5)
