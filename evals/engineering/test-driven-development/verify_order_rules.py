"""Exit 0 when validate_order enforces the 50-unit cap and the 10.00 discount
minimum, and the work tree's own tests catch each rule being dropped or moved by
one. The mutants wrap the work tree's own validate_order, so its messages stay."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "_mutation", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mutation.py"))
mutation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mutation)

HIDDEN = r'''
import sys
from decimal import Decimal
sys.path.insert(0, sys.argv[1])
from orders.model import Line, Order
from orders.validation import ValidationError, validate_order

def order(*lines, code=""):
    return Order("C-1", [Line(s, q, Decimal(p)) for s, q, p in lines], code)

def outcome(o):
    try:
        validate_order(o)
        return "accepted"
    except ValidationError:
        return "rejected"
    except Exception as exc:
        return "raised " + type(exc).__name__

problems = []
def expect(label, o, want):
    got = outcome(o)
    if got != want:
        problems.append(f"{label}: {got}, want {want}")

expect("50 units", order(("A", 50, "1.00")), "accepted")
expect("51 units", order(("A", 51, "1.00")), "rejected")
expect("51 units on the second line", order(("A", 1, "1.00"), ("B", 51, "1.00")), "rejected")
expect("40 + 40 units on two lines", order(("A", 40, "1.00"), ("B", 40, "1.00")), "accepted")
expect("discount on a 10.00 subtotal", order(("A", 2, "5.00"), code="SPRING10"), "accepted")
expect("discount on a 9.99 subtotal", order(("A", 1, "9.99"), code="SPRING10"), "rejected")
expect("discount on 10.00 that is 9.00 after the discount", order(("A", 1, "10.00"), code="SPRING10"), "accepted")
expect("no discount on a 9.99 subtotal", order(("A", 1, "9.99")), "accepted")
expect("unknown code", order(("A", 3, "5.00"), code="FREE"), "rejected")
for p in problems:
    print("FAIL:", p)
sys.exit(1 if problems else 0)
'''

COMMON = '''
import copy
from decimal import Decimal
import orders.validation as _m
from orders.pricing import DISCOUNTS, subtotal
_orig = _m.validate_order
ValidationError = _m.ValidationError
def _valid_code(order):
    return order.discount_code in DISCOUNTS
'''

MUTANTS = {
    "the 50-unit cap is dropped": COMMON + '''
def validate_order(order):
    o = copy.deepcopy(order)
    for line in o.lines:
        line.quantity = min(line.quantity, 50)
    return _orig(o)
swap(_m, "validate_order", validate_order)
''',
    "exactly 50 units is rejected": COMMON + '''
def validate_order(order):
    if any(line.quantity == 50 for line in order.lines):
        raise ValidationError("too many units")
    return _orig(order)
swap(_m, "validate_order", validate_order)
''',
    "the 10.00 discount minimum is dropped": COMMON + '''
def validate_order(order):
    o = copy.deepcopy(order)
    if _valid_code(o) and subtotal(o) < Decimal("10.00"):
        o.discount_code = ""
    return _orig(o)
swap(_m, "validate_order", validate_order)
''',
    "a discount on exactly 10.00 is rejected": COMMON + '''
def validate_order(order):
    if _valid_code(order) and subtotal(order) == Decimal("10.00"):
        raise ValidationError("subtotal too low for a discount")
    return _orig(order)
swap(_m, "validate_order", validate_order)
''',
}


def check(workdir):
    return mutation.hidden(workdir, HIDDEN) + mutation.suite_catches(workdir, "", MUTANTS)


if __name__ == "__main__":
    mutation.main(check)
