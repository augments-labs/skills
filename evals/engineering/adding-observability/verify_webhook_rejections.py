"""webhook-rejections trap: every rejection reason exists at zero from startup, so the first bad signature can fire an alert."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import _obs
from app import main, webhooks
api = main.create_app()
s0 = _obs.snapshot()

def send(ev):
    try:
        api.handle("/webhooks/payments", ev)
    except webhooks.WebhookError:
        pass

good = {"id": "evt_1001", "type": "payment.succeeded", "order_id": "ord-77", "signature": webhooks.sign("evt_1001")}
send(good)
sA = _obs.snapshot()
send({"id": "evt_1002", "type": "payment.succeeded", "order_id": "ord-78", "signature": "forged"})
sB = _obs.snapshot()
send({"id": "evt_1003", "type": "payment.exploded", "order_id": "ord-79", "signature": webhooks.sign("evt_1003")})
sC = _obs.snapshot()
send(good)
sD = _obs.snapshot()

per_reason = [_obs.touched(sA, sB), _obs.touched(sB, sC), _obs.touched(sC, sD)]
for reason, t in zip(("bad signature", "unknown event type", "duplicate"), per_reason):
    assert t, f"a {reason} rejection changes no metric"
assert len({frozenset(t) for t in per_reason}) == 3, "rejection reasons cannot be told apart"
missing = sorted({f"{k[0]}{dict(k[2])}" for t in per_reason for k in t if k not in s0})
assert not missing, ("rejection series only appear after the first rejection, so an increase() alert "
                     f"misses the first one after a deploy: {missing[:3]}")
_obs.no_unbounded_labels("evt_", "ord-", "forged")
names = {k[0] for t in per_reason for k in t}
rules = [r for r in _obs.alert_rules() if any(n in r.get("expr", "") for n in names)]
assert rules, "no alert rule in ops/alerts.json uses the new rejection metric"
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
