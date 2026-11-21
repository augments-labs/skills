import unittest

from quota.clock import FakeClock
from quota.limiter import FixedLimiter
from quota.middleware import check_request


class FixedLimiterTest(unittest.TestCase):
    def test_limit_per_window(self):
        lim = FixedLimiter(2, 60)
        self.assertEqual([lim.allow("k", 1), lim.allow("k", 2), lim.allow("k", 3)], [True, True, False])

    def test_new_window_resets(self):
        lim = FixedLimiter(1, 60)
        self.assertTrue(lim.allow("k", 59))
        self.assertTrue(lim.allow("k", 60))

    def test_middleware(self):
        clock = FakeClock()
        lim = FixedLimiter(1, 10)
        self.assertEqual([check_request(lim, "k", clock), check_request(lim, "k", clock)], [200, 429])
