"""Exit 0 when shop.api.quote gives the right price for every SKU and region in any call order."""
import json
import os
import random
import subprocess
import sys
import time
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

root = Path(sys.argv[1]).resolve()
DEADLINE = time.monotonic() + 110
env = dict(os.environ, PYTHONPATH=str(root), PYTHONDONTWRITEBYTECODE="1")

PRICES_USD = {
    "mug": "12.00", "tee": "24.50", "cap": "18.99", "poster": "9.95",
    "hoodie": "54.00", "sticker": "1.20", "lamp": "26.95", "beanie": "21.30",
}
REGIONS = {
    "US": ("USD", Decimal("1"), Decimal("0")),
    "EU": ("EUR", Decimal("0.92"), Decimal("0.21")),
    "UK": ("GBP", Decimal("0.79"), Decimal("0.20")),
}


def fail(msg):
    print(msg)
    sys.exit(1)


def budget(timeout):
    left = DEADLINE - time.monotonic()
    if left < 1:
        fail("verifier ran out of time")
    return min(timeout, left)


def expected(sku, region):
    currency, rate, vat = REGIONS[region]
    base = Decimal(PRICES_USD[sku])
    if region == "US":
        return str(base), currency
    return str((base * rate * (1 + vat)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)), currency


RUN = r"""
import json, sys
from decimal import Decimal
from shop.api import quote
out = []
for sku, region in json.loads(sys.argv[1]):
    p = quote(sku, region)
    out.append([sku, region, str(Decimal(p.amount).quantize(Decimal("0.01"))), p.currency])
print(json.dumps(out))
"""


def run_order(label, calls):
    try:
        p = subprocess.run([sys.executable, "-c", RUN, json.dumps(calls)], cwd=root, env=env,
                           timeout=budget(10), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired:
        fail(f"quote() timed out ({label})")
    if p.returncode != 0:
        err = [ln for ln in p.stderr.decode("utf-8", "replace").splitlines() if ln.strip()]
        fail(f"quote() raised ({label}): {err[-1][-200:] if err else p.returncode}")
    try:
        rows = json.loads(p.stdout.decode().strip().splitlines()[-1])
    except (ValueError, IndexError):
        fail(f"quote() run printed unexpected output ({label})")
    for sku, region, amount, currency in rows:
        want = expected(sku, region)
        if (amount, currency) != want:
            fail(f"quote({sku!r}, {region!r}) gave {amount} {currency}, expected "
                 f"{want[0]} {want[1]} ({label})")


def main():
    skus = sorted(PRICES_USD)
    regions = list(REGIONS)
    matrix = [(s, r) for s in skus for r in regions]
    orders = {
        "region by region": [(s, r) for r in regions for s in skus],
        "EU first": [(s, r) for r in ("EU", "US", "UK") for s in skus],
        "UK first": [(s, r) for r in ("UK", "EU", "US") for s in skus],
        "per SKU": matrix,
        "per SKU reversed": [(s, r) for s in skus for r in reversed(regions)],
    }
    rng = random.Random(20260301)
    for i in range(4):
        shuffled = matrix[:]
        rng.shuffle(shuffled)
        orders[f"shuffle {i + 1}"] = shuffled
    for label, calls in orders.items():
        run_order(label, calls + calls)

    try:
        p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."],
                           cwd=root, env=env, timeout=budget(60), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired:
        fail("unit tests timed out")
    if p.returncode != 0:
        err = [ln for ln in p.stderr.decode("utf-8", "replace").splitlines() if ln.strip()]
        fail("unit tests fail: " + (err[-1] if err else str(p.returncode)))
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except BaseException as e:
    fail(f"verifier could not inspect quote(): {type(e).__name__}: {e}")
