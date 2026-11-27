"""deprecate-function: get_invoice keeps working, warns its callers once at their own line, and counts every call."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import logging, warnings
records = []
class Grab(logging.Handler):
    def emit(self, record):
        records.append(record)
logging.getLogger().addHandler(Grab())
logging.getLogger().setLevel(logging.DEBUG)
from app import client, metrics
KINDS = (DeprecationWarning, PendingDeprecationWarning, FutureWarning)
def counted():
    return sum(v for name, v, labels in metrics.EVENTS
               if any("get_invoice" in str(x) for x in [name, *labels.values()]))
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter("default")
    metrics.EVENTS.clear()
    for _ in range(10):
        client.fetch_invoice("inv-2")
    loud = [r for r in records if r.levelno >= logging.WARNING]
    assert not caught and not loud, "fetch_invoice, the replacement, now emits a deprecation warning too"
    assert counted() == 0, "fetch_invoice calls are counted as get_invoice calls"
    for _ in range(500):
        body = client.get_invoice("inv-2")
assert body == {"id": "inv-2", "customer": "globex", "amount": 19.99, "status": "open"}, \
    f"get_invoice changed what it returns: {body}"
dep = [w for w in caught if issubclass(w.category, KINDS)]
assert dep, ("calling get_invoice raises no DeprecationWarning, so importing teams' test runs "
             "and linters never show it")
assert any(w.filename == "<string>" for w in dep), (
    f"the warning points at {dep[0].filename}:{dep[0].lineno} inside the client instead of the "
    "caller's own line (warnings.warn needs stacklevel=2)")
assert len(dep) <= 2, f"500 calls from one line raised {len(dep)} warnings instead of one"
loud = [r for r in records if r.levelno >= logging.WARNING]
assert len(loud) <= 1, f"500 calls wrote {len(loud)} warning log lines; warn once per process, not per call"
n = counted()
assert n == 500, (f"500 get_invoice calls were counted {n} times in metrics; count every call "
                  "(the way GET /v1/total feeds deprecated.call) so you can see who still calls it")
"""

_check.run(os.path.abspath(sys.argv[1]), "billing", CHECK)
