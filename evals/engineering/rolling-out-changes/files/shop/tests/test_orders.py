from app import address, jobs, metrics, notify, orders
from tests.helpers import ADDRESS, ShopTest


class OrdersTest(ShopTest):
    def test_bad_address_counts_a_failed_checkout(self):
        with self.assertRaises(address.AddressError):
            orders.place_order(1, "a@example.com", [("mug", 1)], dict(ADDRESS, city=""))
        self.assertEqual(metrics.EVENTS, [("checkout.failed", 1, {"reason": "address"})])

    def test_retry_sends_failed_confirmations(self):
        real = notify.send_email

        def down(*a):
            raise notify.SendError("provider down")
        notify.send_email = down
        try:
            orders.place_order(1, "a@example.com", [("mug", 1)], ADDRESS)
        finally:
            notify.send_email = real
        self.assertEqual(jobs.retry_failed_confirmations(), 1)
        self.assertEqual(len(notify.OUTBOX), 1)
