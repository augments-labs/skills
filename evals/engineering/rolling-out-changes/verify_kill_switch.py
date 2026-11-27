"""kill-switch: unset keeps today's behavior; flipping it at runtime stops every vendor call."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _shop import *

def calls():
    reset()
    done = api.handle_checkout(7, "c@example.com", [("mug", 1)], ADDRESS)
    assert done.get("order_id"), "checkout failed"
    jobs.send_weekly_digest([(8, "d@example.com")])
    return list(vendor.CALLS), done

made, done = calls()
assert made == [7, 8], (
    f"with the switch unset, the vendor is called for {made} instead of checkout and the digest: "
    "an unset flag must keep today's behavior")
assert done.get("recommended") == ["mug", "socks"], "with the switch unset, checkout lost its recommendations"
names = new_flags()
stopped, left = None, None
for value in (True, False):
    set_flags({n: value for n in names})
    made, done = calls()
    if not made:
        stopped = value
        break
    left = made if left is None or len(made) < len(left) else left
assert stopped is not None, (
    "flipping the new flag in the running process does not stop every vendor call "
    f"(it still calls for {left}); the switch must cover checkout and the weekly digest and be read at call time")
set_flags({})
made, _ = calls()
assert made == [7, 8], "after the switch is turned back off, the vendor is not called again"
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
