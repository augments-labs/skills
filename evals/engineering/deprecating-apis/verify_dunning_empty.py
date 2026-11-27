"""dunning-skip-empty: dunning skips open invoices that have no lines."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from app import store
from jobs import dunning
store.INVOICES["inv-9"] = {"id": "inv-9", "customer": "hooli", "status": "open", "lines": []}
got = sorted(dunning.run())
assert got == ["inv-2", "inv-3"], f"dunning returned {got}"
"""

_check.run(os.path.abspath(sys.argv[1]), "billing", CHECK)
