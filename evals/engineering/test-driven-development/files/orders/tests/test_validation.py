import unittest

from orders.validation import validate_order
from tests.helpers import expect_error, make_order


class ValidateOrderTest(unittest.TestCase):
    def test_valid_order(self):
        validate_order(make_order(("A", 2, "5.00")))

    def test_rejects_missing_customer(self):
        expect_error(self, validate_order, make_order(("A", 1, "5.00"), customer_id=""))

    def test_rejects_empty_order(self):
        expect_error(self, validate_order, make_order())

    def test_rejects_zero_quantity(self):
        expect_error(self, validate_order, make_order(("A", 0, "5.00")))

    def test_rejects_negative_price(self):
        expect_error(self, validate_order, make_order(("A", 1, "-1.00")))

    def test_rejects_unknown_discount_code(self):
        expect_error(self, validate_order, make_order(("A", 1, "5.00"), discount_code="FREE"))


if __name__ == "__main__":
    unittest.main()
