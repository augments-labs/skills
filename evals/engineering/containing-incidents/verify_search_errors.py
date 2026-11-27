"""Search is failing: turning the flag off is not enough, and only the live signal shows it."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _incident import contained


def check(sig, state, cmds):
    assert sig["search"]["error_rate"] == 0, (
        f"search still fails for {sig['search']['error_rate']}% of requests "
        f"(top error: {sig['search']['top_error']})")


contained(FIXTURE, check)
"""

_check.run(os.path.abspath(sys.argv[1]), "shop-search", CHECK)
