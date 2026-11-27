import unittest

from app import main, payments, search, store, webhooks
from app.checkout import checkout


class OkGateway(payments.Gateway):
    def charge(self, user_id, amount_cents):
        return f"rcpt-{user_id}"


class ShopTest(unittest.TestCase):
    def test_checkout(self):
        main.create_app()
        cart = {"lines": [{"price_cents": 500, "qty": 1}]}
        self.assertEqual(checkout("u1", cart, OkGateway())["total_cents"], 500)

    def test_search(self):
        self.assertEqual(search.search("mug"), ["red mug", "blue mug"])

    def test_webhook(self):
        ev = {"id": "evt_t1", "type": "payment.succeeded", "order_id": "ord-9",
              "signature": webhooks.sign("evt_t1")}
        self.assertEqual(webhooks.handle(ev), {"ok": True})

    def test_order_total(self):
        self.assertEqual(store.order_total({"lines": [{"price_cents": 250, "qty": 1}]}), 250)


if __name__ == "__main__":
    unittest.main()
