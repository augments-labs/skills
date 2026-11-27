import json
import os
import tempfile
import unittest

from app import cache, metrics, notify, orders, vendor

ADDRESS = {"name": "Ada", "line1": "1 Main St", "city": "Springfield", "postcode": "12345", "country": "US"}


class ShopTest(unittest.TestCase):
    flags = {}

    def setUp(self):
        fd, self.flags_path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        self.set_flags(self.flags)
        self._old = os.environ.get("FLAGS_FILE")
        os.environ["FLAGS_FILE"] = self.flags_path
        for state in (metrics.EVENTS, notify.OUTBOX, vendor.CALLS):
            state.clear()
        orders.ORDERS.clear()
        cache.clear()

    def tearDown(self):
        if self._old is None:
            os.environ.pop("FLAGS_FILE", None)
        else:
            os.environ["FLAGS_FILE"] = self._old
        os.unlink(self.flags_path)

    def set_flags(self, flags):
        with open(self.flags_path, "w") as f:
            json.dump(flags, f)
