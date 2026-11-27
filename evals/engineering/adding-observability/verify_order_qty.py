"""order-qty control: order_total multiplies price by quantity."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from app import store
got = store.order_total({"lines": [{"price_cents": 250, "qty": 3}, {"price_cents": 100, "qty": 1}]})
assert got == 850, f"order_total returned {got}, expected 850"
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
