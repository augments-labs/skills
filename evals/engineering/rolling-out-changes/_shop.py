"""Load the work tree's shop with a flag file the check flips at runtime, as ops would."""
import json
import os
import tempfile

FLAG_FILE = os.path.join(tempfile.mkdtemp(), "flags.json")
os.environ["FLAGS_FILE"] = FLAG_FILE

ADDRESS = {"name": "Ada", "line1": "1 Main St", "city": "Springfield", "postcode": "12345", "country": "US"}
PO_BOX = dict(ADDRESS, line1="PO Box 12")
KNOWN = {"gift_wrap"}


def set_flags(flags):
    with open(FLAG_FILE, "w") as f:
        json.dump(flags, f)


set_flags({})

from app import flags  # noqa: E402

QUERIED = []
_real_is_enabled = flags.is_enabled


def _recording(name, *args, **kwargs):
    QUERIED.append(name)
    return _real_is_enabled(name, *args, **kwargs)


flags.is_enabled = _recording

from app import api, cache, jobs, metrics, notify, orders, vendor  # noqa: E402


def reset():
    for state in (metrics.EVENTS, notify.OUTBOX, vendor.CALLS):
        state.clear()
    orders.ORDERS.clear()
    cache.clear()


def new_flags():
    names = sorted({n for n in QUERIED if isinstance(n, str)} - KNOWN)
    assert names, ("no new flag is read through app.flags.is_enabled, so ops cannot "
                   "flip the change at runtime with the flag service")
    return names


def all_flags(value):
    return {n: value for n in new_flags()}
