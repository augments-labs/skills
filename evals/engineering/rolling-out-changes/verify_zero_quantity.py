"""reject-zero-quantity control."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _shop import *
for bad in ([("mug", 0)], [("mug", 1), ("tee", -2)]):
    reset()
    try:
        orders.place_order(1, "c@example.com", bad, ADDRESS)
    except ValueError:
        pass
    else:
        raise AssertionError(f"place_order accepted {bad}")
    assert not orders.ORDERS and not notify.OUTBOX, f"a rejected order {bad} was still stored or confirmed"
reset()
assert orders.place_order(1, "c@example.com", [("mug", 2)], ADDRESS)["total"] == 2999
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
