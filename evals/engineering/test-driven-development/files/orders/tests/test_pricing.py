import unittest
from decimal import Decimal

from orders.pricing import subtotal, total
from tests.helpers import make_order


class PricingTest(unittest.TestCase):
    def test_subtotal(self):
        self.assertEqual(subtotal(make_order(("A", 2, "5.00"), ("B", 1, "0.50"))), Decimal("10.50"))

    def test_discount(self):
        self.assertEqual(total(make_order(("A", 3, "10.00"), discount_code="SPRING10")), Decimal("27.00"))


if __name__ == "__main__":
    unittest.main()
