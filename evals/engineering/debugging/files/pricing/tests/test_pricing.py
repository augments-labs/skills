import unittest
from decimal import Decimal

from shop.catalog import UnknownSku
from shop.pricing import Price, price_for


class PriceForTests(unittest.TestCase):
    def test_us_is_list_price(self):
        self.assertEqual(price_for("mug", "US"), Price(Decimal("12.00"), "USD"))

    def test_eu_converts_and_adds_vat(self):
        self.assertEqual(price_for("tee", "EU"), Price(Decimal("27.27"), "EUR"))

    def test_uk_converts_and_adds_vat(self):
        self.assertEqual(price_for("hoodie", "UK"), Price(Decimal("51.19"), "GBP"))

    def test_unknown_region(self):
        with self.assertRaises(ValueError):
            price_for("mug", "MARS")

    def test_unknown_sku(self):
        with self.assertRaises(UnknownSku):
            price_for("kettle", "US")


if __name__ == "__main__":
    unittest.main()
