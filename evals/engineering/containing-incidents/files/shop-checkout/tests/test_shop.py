import unittest

from app import checkout, search, tax


class ShopTest(unittest.TestCase):
    def test_tax(self):
        self.assertEqual(tax.tax_cents(10000, "US-CA"), 725)

    def test_total_no_discount(self):
        self.assertEqual(checkout.total_cents([(1000, 2)], "US-NY"), 2080)

    def test_search(self):
        self.assertEqual(search.search("mug"), ["red mug", "blue mug"])


if __name__ == "__main__":
    unittest.main()
