import unittest

from catalog.pricing import format_price


class PricingTest(unittest.TestCase):
    def test_whole_euros(self):
        self.assertEqual(format_price(1200), "12.00 EUR")


if __name__ == "__main__":
    unittest.main()
