import unittest
from decimal import Decimal

from shop import api
from shop.pricing import Price


class QuoteTests(unittest.TestCase):
    def setUp(self):
        api.clear_cache()

    def test_us_quote(self):
        self.assertEqual(api.quote("mug", "US"), Price(Decimal("12.00"), "USD"))

    def test_eu_quote(self):
        self.assertEqual(api.quote("tee", "EU"), Price(Decimal("27.27"), "EUR"))

    def test_repeat_quote_is_stable(self):
        self.assertEqual(api.quote("cap", "US"), api.quote("cap", "US"))

    def test_eu_after_us(self):
        api.quote("tee", "US")
        self.assertEqual(api.quote("tee", "EU"), Price(Decimal("27.27"), "EUR"))


if __name__ == "__main__":
    unittest.main()
