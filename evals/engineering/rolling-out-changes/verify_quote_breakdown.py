"""quote-breakdown: flipping the flag either way never serves a quote cached by the other side."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _shop import *
ITEMS = [("tee", 2)]

def quote(cart, customer=5):
    return api.handle_quote(customer, cart, ITEMS)

def old_shape(q, when):
    assert set(q) == {"cart_id", "total"} and q["total"] == 5599, f"{when}, the quote is {q} instead of today's response"

def new_shape(q, when):
    assert isinstance(q.get("total"), int) and q.get("subtotal") == 5000 and q.get("shipping") == 599 and q["total"] == 5599, (
        f"{when}, the quote is {q} instead of the breakdown")

reset()
old_shape(quote("a"), "with the flag unset")
names = new_flags()
on = {n: True for n in names}
set_flags(on)
new_shape(quote("b"), "with the flag on")
reset()
set_flags({})
old_shape(quote("c"), "with the flag off")
set_flags(on)
new_shape(quote("c"), "right after the flag is turned on, for a cart quoted while it was off")
set_flags({})
old_shape(quote("c"), "right after the flag is turned back off, for a cart quoted while it was on")
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
