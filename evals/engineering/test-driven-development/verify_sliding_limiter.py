"""Exit 0 when SlidingLimiter enforces a per-key sliding window exactly as asked
and the work tree's own tests catch each limit, window edge, and rule being off."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "_mutation", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mutation.py"))
mutation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mutation)

HIDDEN = r'''
import sys
sys.path.insert(0, sys.argv[1])
from quota.limiter import SlidingLimiter

problems = []
def expect(label, got, want):
    if got != want:
        problems.append(f"{label}: got {got!r}, want {want!r}")

lim = SlidingLimiter(3, 10)
expect("3 per 10s, calls at 0, 1, 2, 3", [lim.allow("k", t) for t in (0, 1, 2, 3)], [True, True, True, False])
expect("the call at 0 stops counting at exactly 10", lim.allow("k", 10), True)
expect("calls at 1, 2, 10 still count at 10.5", lim.allow("k", 10.5), False)
expect("the call at 1 stops counting at 11", lim.allow("k", 11), True)

lim = SlidingLimiter(1, 10)
expect("denied calls do not count", [lim.allow("k", t) for t in (0, 5, 10)], [True, False, True])

lim = SlidingLimiter(2, 60)
got = [lim.allow("a", 0), lim.allow("a", 1), lim.allow("b", 2), lim.allow("b", 3), lim.allow("a", 4), lim.allow("b", 5)]
expect("keys are independent", got, [True, True, True, True, False, False])

lim = SlidingLimiter(100, 1)
expect("100 per second", sum(lim.allow("k", 0.001 * i) for i in range(150)), 100)

for args in ((0, 10), (3, 0), (3, -1)):
    try:
        SlidingLimiter(*args)
        problems.append(f"SlidingLimiter{args} did not raise ValueError")
    except ValueError:
        pass
for p in problems:
    print("FAIL:", p)
sys.exit(1 if problems else 0)
'''

TEMPLATE = '''
import collections
import quota.limiter as _m

class SlidingLimiter:
    def __init__(self, limit, window):
        __VALIDATE__
        self.limit = limit
        self.window = window
        self._calls = collections.defaultdict(collections.deque)

    def allow(self, key, now):
        q = self._calls[__KEY__]
        while q and __EXPIRED__:
            q.popleft()
        if len(q) >= __LIMIT__:
            __DENIED__
            return False
        q.append(now)
        return True

swap(_m, "SlidingLimiter", SlidingLimiter)
'''
GOOD = {
    "__VALIDATE__": 'if limit < 1 or window <= 0:\n            raise ValueError("limit must be >= 1 and window > 0")',
    "__KEY__": "key", "__EXPIRED__": "q[0] <= now - self.window",
    "__LIMIT__": "self.limit", "__DENIED__": "pass",
}


def patch(**changes):
    src = TEMPLATE
    for key, value in dict(GOOD, **changes).items():
        src = src.replace(key, value)
    return src


MUTANTS = {
    "one call over the limit is allowed": patch(__LIMIT__="self.limit + 1"),
    "the last call within the limit is denied": patch(__LIMIT__="self.limit - 1"),
    "a call exactly one window earlier still counts": patch(__EXPIRED__="q[0] < now - self.window"),
    "denied calls count toward the limit": patch(__DENIED__="q.append(now)"),
    "all keys share one quota": patch(__KEY__="None"),
    "calls never expire": patch(__EXPIRED__="False"),
    "an invalid limit or window is accepted": patch(__VALIDATE__="pass"),
}


def check(workdir):
    return mutation.hidden(workdir, HIDDEN) + mutation.suite_catches(workdir, patch(), MUTANTS)


if __name__ == "__main__":
    mutation.main(check)
