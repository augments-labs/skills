"""Exit 0 when the refactored summarize() and summary_csv() still give exactly the
original output on a battery of orders, and the work tree's own tests catch each
behavior the original pins (rounding, ties, grouping, statuses) being changed."""
import importlib.util
import os
import sys

_spec = importlib.util.spec_from_file_location(
    "_mutation", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mutation.py"))
mutation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mutation)

ORIGINAL = 'from decimal import ROUND_HALF_EVEN, Decimal\n\nCENT = Decimal("0.01")\n\n\ndef summarize(orders, top=3):\n    """Summarize a month of orders for finance.\n\n    Returns {"orders": int, "total": str, "average": str, "top_customers": [[name, total], ...]}.\n    """\n    count = 0\n    total = Decimal("0")\n    per_customer = {}\n    names = {}\n    for order in orders:\n        status = (order.get("status") or "").strip().lower()\n        if status == "cancelled" or status == "void":\n            continue\n        amount = Decimal(str(order["amount"]).strip())\n        if status == "refunded":\n            amount = -amount\n        else:\n            if status != "paid":\n                if status == "pending":\n                    continue\n                raise ValueError(f"order {order.get(\'id\')}: unknown status {order.get(\'status\')!r}")\n        count += 1\n        total += amount\n        raw = (order.get("customer") or "").strip()\n        key = raw.casefold()\n        if key not in per_customer:\n            per_customer[key] = Decimal("0")\n            names[key] = raw if raw else "(no name)"\n        per_customer[key] += amount\n    if count:\n        average = (total / count).quantize(CENT, rounding=ROUND_HALF_EVEN)\n    else:\n        average = Decimal("0").quantize(CENT)\n    ranked = []\n    for key in per_customer:\n        placed = False\n        for i, (other, _) in enumerate(ranked):\n            if per_customer[key] > per_customer[other]:\n                ranked.insert(i, (key, per_customer[key]))\n                placed = True\n                break\n        if not placed:\n            ranked.append((key, per_customer[key]))\n    top_customers = []\n    for key, amount in ranked[:top]:\n        if amount <= 0:\n            continue\n        top_customers.append([names[key], str(amount.quantize(CENT, rounding=ROUND_HALF_EVEN))])\n    return {\n        "orders": count,\n        "total": str(total.quantize(CENT, rounding=ROUND_HALF_EVEN)),\n        "average": str(average),\n        "top_customers": top_customers,\n    }\n'

HIDDEN = r"""
import random
import sys
sys.path.insert(0, sys.argv[1])
from reports.summary import summarize
from reports.export import summary_csv

ref = {}
exec(ORIGINAL_SRC, ref)
CENT = ref["CENT"]

def outcome(fn, *args):
    try:
        return ("ok", fn(*args))
    except Exception as exc:
        return ("raised", type(exc).__name__, str(exc))

def ref_csv(orders):
    import reports.export as ex
    saved = ex.summarize
    ex.summarize = ref["summarize"]
    try:
        return summary_csv(orders)
    finally:
        ex.summarize = saved

def o(i, customer, status, amount):
    return {"id": str(i), "customer": customer, "status": status, "amount": amount}

CASES = [
    [],
    [o(1, "Acme", "cancelled", "5.00")],
    [o(1, "Acme", "paid", "0.005"), o(2, "Acme", "paid", "0.005"), o(3, "Birch", "paid", "0.005")],
    [o(1, "Birch", "paid", "10.00"), o(2, "Acme", "paid", "10.00"), o(3, "Cole", "paid", "10.00"), o(4, "Dee", "paid", "10.00")],
    [o(1, "acme", "paid", "5.00"), o(2, "ACME", "paid", "7.00"), o(3, "Acme", "refunded", "1.00")],
    [o(1, "Acme", "refunded", "30.00"), o(2, "Birch", "paid", "10.00")],
    [o(1, "Acme", " Paid ", " 12.345 "), o(2, "", "PAID", "3.00"), o(3, None, "paid", "1.00")],
    [o(1, "Acme", "void", "9.00"), o(2, "Acme", "pending", "9.00"), o(3, "Birch", "paid", "1.00")],
    [o(1, "Acme", "paid", "1.00"), o(2, "Birch", "shipped", "2.00")],
    [o(1, "Acme", None, "1.00")],
    [o(1, "Acme", "paid", "1.00"), o(2, "Birch", "refunded", "5.00"), o(3, "Cole", "paid", "0.00")],
    [o(1, "Acme", "paid", "2.50"), o(2, "Birch", "paid", "2.50"), o(3, "Cole", "paid", "2.51")],
    [o(1, "Ça", "paid", "1.00"), o(2, "ça", "paid", "1.00"), o(3, "STRASSE", "paid", "1.00"), o(4, "straße", "paid", "1.00")],
    [o(1, "Acme", "paid", "0.125"), o(2, "Acme", "paid", "0.010")],
    [o(1, "Acme", "paid", "1.015"), o(2, "Birch", "paid", "1.025")],
]
rng = random.Random(7)
names = ["Acme", "acme", "ACME", "Birch", " birch ", "Cole", "", None, "Dee"]
statuses = ["paid"] * 6 + ["Paid ", " PAID", "refunded", "refunded", "cancelled", "void", "pending", "Cancelled"]
for n in range(400):
    k = rng.randint(0, 9)
    orders = []
    for i in range(k):
        cents = rng.choice([rng.randint(0, 5000), rng.randint(0, 9)])
        amount = f"{cents // 100}.{cents % 100:02d}"
        if rng.random() < 0.25:
            amount = f"{rng.randint(0, 20)}.{rng.randint(0, 999):03d}"
        if rng.random() < 0.1:
            amount = " " + amount + " "
        orders.append(o(i, rng.choice(names), rng.choice(statuses), amount))
    if rng.random() < 0.02:
        orders.append(o(99, "Acme", "lost", "1.00"))
    CASES.append(orders)

problems = []
for n, orders in enumerate(CASES):
    for top in (3, 1, 5):
        want = outcome(ref["summarize"], orders, top)
        got = outcome(summarize, orders, top)
        if got != want:
            problems.append(f"summarize({orders!r}, top={top}) gave {got!r}, the original gave {want!r}")
            break
    else:
        if outcome(summary_csv, orders) != outcome(ref_csv, orders):
            problems.append(f"summary_csv({orders!r}) changed")
    if len(problems) >= 3:
        break
for p in problems:
    print("FAIL:", p)
sys.exit(1 if problems else 0)
""".replace("ORIGINAL_SRC", repr(ORIGINAL))


def variant(*edits):
    src = ORIGINAL
    for old, new in edits:
        if src.count(old) != 1:
            raise SystemExit(f"mutant edit does not apply once: {old!r}")
        src = src.replace(old, new)
    return src + '\nimport reports.summary as _m\nswap(_m, "summarize", summarize)\n'


MUTANTS = {
    "amounts are rounded per order instead of at the end": variant(
        ('amount = Decimal(str(order["amount"]).strip())',
         'amount = Decimal(str(order["amount"]).strip()).quantize(CENT, rounding=ROUND_HALF_EVEN)')),
    "tied customers are ordered by name instead of first appearance": variant(
        ("if per_customer[key] > per_customer[other]:",
         "if (-per_customer[key], names[key]) < (-per_customer[other], names[other]):")),
    "refunds are left out of the order count": variant(
        ("        count += 1\n", "        count += status != \"refunded\"\n")),
    "void orders raise instead of being skipped": variant(
        ('if status == "cancelled" or status == "void":', 'if status == "cancelled":')),
    "customers are grouped case-sensitively": variant(
        ("key = raw.casefold()", "key = raw")),
    "a customer shows the last spelling seen instead of the first": variant(
        ("        per_customer[key] += amount\n",
         "        per_customer[key] += amount\n        names[key] = raw if raw else \"(no name)\"\n")),
    "a customer with no name shows as blank instead of (no name)": variant(
        ('names[key] = raw if raw else "(no name)"', "names[key] = raw")),
    "the average rounds half up instead of half to even": variant(
        ("average = (total / count).quantize(CENT, rounding=ROUND_HALF_EVEN)",
         "average = (total / count).quantize(CENT, rounding='ROUND_HALF_UP')")),
}


def check(workdir):
    return mutation.hidden(workdir, HIDDEN) + mutation.suite_catches(workdir, variant(), MUTANTS)


if __name__ == "__main__":
    mutation.main(check)
