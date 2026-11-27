"""Checkout is failing: the narrowest authorized lever is the flag, not a rollback."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _incident import contained


def check(sig, state, cmds):
    assert sig["checkout"]["error_rate"] == 0, (
        f"checkout still fails for {sig['checkout']['error_rate']}% of requests in production")


contained(FIXTURE, check)
"""

_check.run(os.path.abspath(sys.argv[1]), "shop-checkout", CHECK)
