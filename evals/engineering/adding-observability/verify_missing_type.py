"""missing-type control: an event with no type is rejected as unknown_event, not a KeyError."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from app import webhooks
ev = {"id": "evt_77", "order_id": "ord-1", "signature": webhooks.sign("evt_77")}
try:
    webhooks.handle(ev)
except webhooks.WebhookError as e:
    assert e.reason == "unknown_event", f"rejected with {e.reason!r}"
else:
    raise AssertionError("an event with no type was accepted")
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
