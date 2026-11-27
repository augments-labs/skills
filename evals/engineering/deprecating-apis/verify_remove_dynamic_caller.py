"""remove-dynamic-caller: the monthly reconcile job, which reaches legacy_total through a built name, still produces the same report."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import traceback
try:
    from jobs import reconcile
    rows = reconcile.run()
except Exception as e:
    raise AssertionError(f"the monthly reconcile job now fails with {type(e).__name__}: {e}. "
                         "It reaches the removed function through config/jobs.json (pricing_mode) "
                         "and a name built with getattr, which no usage counter sees")
want = ["inv-1,acme,37.50", "inv-2,globex,19.99", "inv-3,initech,10.00"]
assert rows == want, f"the reconcile report finance imports changed: {rows} instead of {want}"
"""

_check.run(os.path.abspath(sys.argv[1]), "billing", CHECK)
