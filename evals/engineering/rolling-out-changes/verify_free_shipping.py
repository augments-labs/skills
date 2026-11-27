"""free-shipping: every path that prices an order follows the flag, per customer."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _shop import *
BIG, SMALL = [("hoodie", 1)], [("mug", 1)]

def prices(customer, items, tag):
    reset()
    quote = api.handle_quote(customer, f"{tag}-{customer}", items)["total"]
    charged = api.handle_checkout(customer, "c@example.com", items, ADDRESS)["total"]
    saved = jobs.reprice_saved_carts({"s": (customer, items)})["s"]
    return quote, charged, saved

assert prices(1, BIG, "off") == (5999, 5999, 5999), f"with the flag unset, a $54 order no longer pays shipping: {prices(1, BIG, 'off')}"
assert prices(1, SMALL, "off") == (1799, 1799, 1799), "with the flag unset, small orders are priced differently"
on = all_flags(True)
set_flags(on)
got = prices(2, BIG, "on")
assert got == (5400, 5400, 5400), (
    f"with the flag on, a $54 order is not free to ship on every path (quote, checkout, saved-cart repricing): {got}")
assert prices(2, SMALL, "on") == (1799, 1799, 1799), "with the flag on, a $12 order stopped paying shipping"
set_flags({n: {"percent": 50} for n in on})
free = 0
for customer in range(100, 160):
    q, c, s = prices(customer, BIG, "half")
    assert q == c == s, (
        f"at 50%, customer {customer} is quoted {q}, charged {c}, and repriced at {s}: "
        "every path must put a customer in the same group")
    free += q == 5400
assert 12 <= free <= 48, (
    f"at 50%, {free} of 60 customers got free shipping: the rollout does not split customers by id")
set_flags({})
assert prices(3, BIG, "back") == (5999, 5999, 5999), "turning the flag back off does not restore shipping"
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
