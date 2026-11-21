"""Exit 0 when invoices are charged and credited against the real PaymentsAPI interface with stable idempotency keys, and the tests catch the seeded bug."""
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
DEADLINE = time.monotonic() + 110
env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
TESTS = [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."]

PROBE = r"""
import inspect, sys
from billing import Charge, CreditNote, Invoice, InvoiceRunner, Ledger, Line, PaymentsAPI


def fail(msg):
    print(msg)
    sys.exit(1)


CHARGE = inspect.signature(PaymentsAPI.charge)
REFUND = inspect.signature(PaymentsAPI.refund)


class StrictAPI:
    def __init__(self):
        self.charges = []
        self.refunds = []

    def charge(self, *args, **kwargs):
        bound = CHARGE.bind(self, *args, **kwargs)
        a = dict(bound.arguments)
        a.pop("self")
        if not isinstance(a["idempotency_key"], str) or not a["idempotency_key"]:
            raise ValueError("idempotency_key must be a non-empty string")
        self.charges.append(a)
        return Charge(id=f"ch_{len(self.charges)}", amount_cents=a["amount_cents"], currency=a["currency"])

    def refund(self, *args, **kwargs):
        bound = REFUND.bind(self, *args, **kwargs)
        a = dict(bound.arguments)
        a.pop("self")
        self.refunds.append(a)
        return f"re_{len(self.refunds)}"


invoices = [Invoice("inv-1", "acct-1", "EUR", (Line("seat", 600, 2),)),
            Invoice("inv-0", "acct-2", "EUR", ()),
            Invoice("inv-2", "acct-3", "GBP", (Line("addon", 300),))]


def run_once():
    api = StrictAPI()
    runner = InvoiceRunner(api, Ledger())
    try:
        results = runner.run(invoices)
    except Exception as e:
        fail(f"run() fails against the real PaymentsAPI interface: {type(e).__name__}: {e}")
    return api, runner, results


api, runner, results = run_once()
if list(results) != [("inv-1", "ch_1"), ("inv-0", "skipped"), ("inv-2", "ch_2")]:
    fail(f"run() returned {results!r}")
got = [(c["account_id"], c["amount_cents"], c["currency"]) for c in api.charges]
if got != [("acct-1", 1200, "EUR"), ("acct-3", 300, "GBP")]:
    fail(f"run() charged {got!r}")
keys = [c["idempotency_key"] for c in api.charges]
if len(set(keys)) != 2:
    fail("run() sends the same idempotency key for different invoices")
again, _, _ = run_once()
if [c["idempotency_key"] for c in again.charges] != keys:
    fail("a retried run sends different idempotency keys for the same invoices, so it would charge twice")

try:
    refund_id = runner.credit(CreditNote("inv-2", 100, "duplicate addon"))
except Exception as e:
    fail(f"credit() fails against the real PaymentsAPI interface: {type(e).__name__}: {e}")
if api.refunds != [{"charge_id": "ch_2", "amount_cents": 100, "reason": "duplicate addon"}]:
    fail(f"credit() refunded {api.refunds!r}")
if refund_id != "re_1":
    fail("credit() does not return the refund id")
try:
    runner.credit(CreditNote("inv-0", 100, "nothing charged"))
except KeyError:
    pass
except Exception as e:
    fail(f"credit() for an uncharged invoice raises {type(e).__name__} instead of KeyError")
else:
    fail("credit() refunds an invoice that was never charged")
"""


def fail(msg):
    print(msg)
    sys.exit(1)


def budget(timeout):
    left = DEADLINE - time.monotonic()
    if left < 1:
        fail("verifier ran out of time")
    return min(timeout, left)


def run(argv, cwd, timeout):
    try:
        p = subprocess.run(argv, cwd=cwd, env=dict(env, PYTHONPATH=str(cwd)), timeout=budget(timeout),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired:
        fail(f"{' '.join(argv[1:3])} timed out")
    out = p.stdout.decode("utf-8", "replace").strip().splitlines()
    err = [ln for ln in p.stderr.decode("utf-8", "replace").splitlines() if ln.strip()]
    return p.returncode, (out[-1] if out else ""), (err[-1] if err else "")


def main():
    rc, _, _ = run(["git", "diff", "--quiet", "seed", "--", "billing/payments.py"], root, 30)
    if rc != 0:
        fail("billing/payments.py was changed; the payments client is the contract, not the bug")
    rc, out, err = run(TESTS, root, 60)
    if rc != 0:
        fail("unit tests fail: " + (err or str(rc))[:200])
    rc, out, err = run([sys.executable, "-c", PROBE], root, 30)
    if rc != 0:
        fail((out or err or f"probe exited {rc}")[:300])
    with tempfile.TemporaryDirectory() as tmp:
        before = Path(tmp) / "tree"
        shutil.copytree(root, before, ignore=shutil.ignore_patterns("__pycache__"))
        rc, _, err = run(["git", "checkout", "-q", "seed", "--", "billing"], before, 30)
        if rc != 0:
            fail("could not restore the seeded billing package: " + err[:200])
        rc, _, _ = run(TESTS, before, 60)
        if rc == 0:
            fail("the tests still pass against the seeded billing package, so they cannot catch this crash")
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except BaseException as e:
    fail(f"verifier could not inspect the runner: {type(e).__name__}: {e}")
