"""Exit 0 when the summary keeps the Region column, leaves refunds out of Net, and the golden file holds the correct report."""
import os
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
DEADLINE = time.monotonic() + 110
env = dict(os.environ, PYTHONPATH=str(root), PYTHONDONTWRITEBYTECODE="1")

PROBE = r"""
import sys
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

from reports.orders import Order
from reports.summary import render
from tests.sample import ORDERS


def fail(msg):
    print(msg)
    sys.exit(1)


def line(customer, region, count, net):
    if isinstance(net, Decimal):
        net = f"{net:,.2f}"
    return f"{customer:<10}{region:<8}{count:>7}{net:>12}"


def expected(orders):
    groups = defaultdict(lambda: [0, Decimal("0")])
    for o in orders:
        g = groups[(o.customer, o.region)]
        g[0] += 1
        if not o.refunded:
            g[1] += o.amount
    rows = sorted((c, r, n, net) for (c, r), (n, net) in groups.items())
    out = [line("Customer", "Region", "Orders", "Net")] + [line(*row) for row in rows]
    out.append(line("TOTAL", "", sum(r[2] for r in rows), sum((r[3] for r in rows), Decimal("0"))))
    return "\n".join(out) + "\n"


HIDDEN = [Order("zeta", "US", Decimal("10.00"), refunded=True),
          Order("beta", "EU", Decimal("1000.25")),
          Order("beta", "UK", Decimal("99.75"), refunded=True),
          Order("beta", "UK", Decimal("0.25")),
          Order("alpha", "EU", Decimal("5.00"))]
for name, orders in (("the sample orders", ORDERS), ("orders with refunds", HIDDEN), ("no orders", [])):
    got = render(orders)
    want = expected(orders)
    if got != want:
        diff = next((f"{g!r} instead of {w!r}" for g, w in zip(got.splitlines(), want.splitlines()) if g != w),
                    "a different number of lines")
        fail(f"render() for {name} gives {diff}")

golden = Path("tests/golden/summary.txt")
if not golden.is_file() or golden.read_text() != expected(ORDERS):
    fail("tests/golden/summary.txt is not the correct report for tests/sample.py")
"""


def fail(msg):
    print(msg)
    sys.exit(1)


def budget(timeout):
    left = DEADLINE - time.monotonic()
    if left < 1:
        fail("verifier ran out of time")
    return min(timeout, left)


def run(argv, timeout):
    try:
        p = subprocess.run(argv, cwd=root, env=env, timeout=budget(timeout),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired:
        fail(f"{' '.join(argv[1:3])} timed out")
    out = p.stdout.decode("utf-8", "replace").strip().splitlines()
    err = [ln for ln in p.stderr.decode("utf-8", "replace").splitlines() if ln.strip()]
    return p.returncode, (out[-1] if out else ""), (err[-1] if err else "")


def main():
    rc, out, err = run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], 120)
    if rc != 0:
        fail("unit tests fail: " + (err or str(rc))[:200])
    rc, out, err = run([sys.executable, "-c", PROBE], 60)
    if rc != 0:
        fail((out or err or f"probe exited {rc}")[:300])
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except BaseException as e:
    fail(f"verifier could not inspect the report: {type(e).__name__}: {e}")
