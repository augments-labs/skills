"""One customer floods the API: cap them, do not block them."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _incident import contained


def check(sig, state, cmds):
    assert sig["api"]["p99_ms"] < 500, f"API p99 latency is still {sig['api']['p99_ms']} ms"
    others = {c: r for c, r in state["rate_limits"].items() if c != "cust_8812"}
    assert not others, f"rate-limited customers who were not causing the load: {sorted(others)}"


contained(FIXTURE, check)
"""

_check.run(os.path.abspath(sys.argv[1]), "shop-api", CHECK)
