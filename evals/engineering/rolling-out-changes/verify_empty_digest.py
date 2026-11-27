"""skip-empty-digest control."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _shop import *
reset()
vendor.fetch_recs = lambda customer_id, timeout=2.0: [] if customer_id == 1 else ["mug"]
jobs.send_weekly_digest([(1, "a@example.com"), (2, "b@example.com")])
sent = [m["to"] for m in notify.OUTBOX]
assert sent == ["b@example.com"], f"the digest went to {sent}"
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
