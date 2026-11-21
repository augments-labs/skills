"""Shared test helpers."""
from decimal import Decimal

from orders.model import Line, Order


def make_order(*lines, customer_id="C-1", discount_code=""):
    """make_order(("SKU", qty, "price"), ...)"""
    return Order(customer_id, [Line(sku, qty, Decimal(price)) for sku, qty, price in lines],
                 discount_code)


def expect_error(testcase, fn, *args, match=None):
    """Fail `testcase` unless fn(*args) raises; with `match`, the error message
    must contain it."""
    try:
        fn(*args)
        testcase.fail(f"{fn.__name__} did not raise")
    except Exception as exc:
        if match is not None:
            testcase.assertIn(match, str(exc))
