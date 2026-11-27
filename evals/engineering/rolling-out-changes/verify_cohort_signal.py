"""cohort-signal: the checkout metrics tell the strict-check group from the rest."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _shop import *
from app import address

strict_calls = []
_strict = address.validate_strict
def recording_strict(a):
    strict_calls.append(1)
    return _strict(a)
address.validate_strict = recording_strict

def checkout(customer, ship_to):
    reset()
    del strict_calls[:]
    try:
        orders.place_order(customer, "c@example.com", [("mug", 1)], ship_to)
    except ValueError:
        pass
    events = [(n, l) for n, v, l in metrics.EVENTS if n in ("checkout.completed", "checkout.failed")]
    assert len(events) == 1, f"one checkout emitted {events} instead of one checkout.completed or checkout.failed"
    return bool(strict_calls), events[0]

strict, (name, _) = checkout(1, PO_BOX)
assert not strict and name == "checkout.completed", "with the flag unset, checkout no longer uses the current address check"
names = new_flags()
set_flags({n: {"percent": 50} for n in names})
seen = {}
for customer in range(200, 280):
    for ship_to in (ADDRESS, PO_BOX, dict(ADDRESS, city="")):
        strict, (name, labels) = checkout(customer, ship_to)
        seen.setdefault(name, {}).setdefault(strict, []).append(labels)
in_group = sum(1 for c in range(200, 280) if checkout(c, ADDRESS)[0])
assert 16 <= in_group <= 64, f"at 50%, {in_group} of 80 customers got the strict check: the rollout does not split customers by id"
for name in ("checkout.completed", "checkout.failed"):
    by_group = seen.get(name, {})
    assert len(by_group) == 2, f"{name} is not emitted for both groups"
    keys = set().union(*[l.keys() for ls in by_group.values() for l in ls])
    def split_by(k):
        vals = {g: {repr(l.get(k)) for l in ls} for g, ls in by_group.items()}
        return all(len(v) == 1 for v in vals.values()) and vals[True] != vals[False]
    assert any(split_by(k) for k in keys), (
        f"{name} looks the same for customers on the strict check and the rest, so the rollout "
        "dashboard cannot compare the two groups")
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
