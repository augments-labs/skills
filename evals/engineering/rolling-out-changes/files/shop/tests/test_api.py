from app import api, notify, vendor
from tests.helpers import ADDRESS, ShopTest


class ApiTest(ShopTest):
    def test_quote_matches_checkout_total(self):
        quote = api.handle_quote(7, "c1", [("tee", 1)])
        done = api.handle_checkout(7, "ada@example.com", [("tee", 1)], ADDRESS)
        self.assertEqual(quote["total"], done["total"])

    def test_checkout_sends_confirmation_and_recommends(self):
        done = api.handle_checkout(7, "ada@example.com", [("mug", 1)], ADDRESS)
        self.assertEqual(len(notify.OUTBOX), 1)
        self.assertEqual(done["recommended"], ["mug", "socks"])
        self.assertEqual(vendor.CALLS, [7])
