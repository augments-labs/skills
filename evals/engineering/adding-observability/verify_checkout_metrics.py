"""checkout-metrics trap: duration and outcome are recorded on failures too, without per-user labels."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import _obs
from app import main, payments
api = main.create_app()

class Ok(payments.Gateway):
    def charge(self, user_id, amount_cents):
        return "rcpt-" + user_id
class Declined(payments.Gateway):
    def charge(self, user_id, amount_cents):
        raise payments.PaymentDeclined("card declined")
class Timeout(payments.Gateway):
    def charge(self, user_id, amount_cents):
        raise payments.PaymentTimeout("gateway timed out")

cart = {"lines": [{"price_cents": 1234, "qty": 1}]}
def call(user, gw):
    try:
        api.handle("/checkout", user, cart, gw)
    except (payments.PaymentDeclined, payments.PaymentTimeout):
        pass

hists = _obs.histograms()
h0 = {n: _obs.hist_count(n) for n in hists}
s0 = _obs.snapshot()
for u in ("u-1001", "u-1002", "u-1003"):
    call(u, Ok())
hA = {n: _obs.hist_count(n) for n in hists}
sA = _obs.snapshot()
call("u-2001", Declined())
call("u-3001", Timeout())
hB = {n: _obs.hist_count(n) for n in hists}
sB = _obs.snapshot()

timed = [n for n in hists if hA[n] - h0[n] >= 3 and hB[n] - hA[n] >= 2]
assert hists, "no latency histogram was added for checkout"
assert timed, ("checkout latency is not recorded when the payment fails: "
               + ", ".join(f"{n} +{hA[n]-h0[n]} ok, +{hB[n]-hA[n]} failed" for n in hists))
okset = _obs.touched(s0, sA)
failset = _obs.touched(sA, sB)
assert failset - okset, "failed checkouts land in the same series as successful ones, so failures cannot be told apart"
_obs.no_unbounded_labels("u-1001", "u-2001", "u-3001", "rcpt-", "1234")
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
