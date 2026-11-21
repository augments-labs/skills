import io
import json
import unittest

from billing import Charge, PaymentError, PaymentsAPI


class FakeOpener:
    def __init__(self, reply):
        self.reply = reply
        self.requests = []

    def __call__(self, request, timeout):
        self.requests.append(request)
        return io.BytesIO(json.dumps(self.reply).encode("utf-8"))


class PaymentsAPITests(unittest.TestCase):
    def test_charge(self):
        opener = FakeOpener({"id": "ch_1", "amount": 1200, "currency": "EUR"})
        api = PaymentsAPI("https://pay.test/", "k", opener=opener)
        charge = api.charge("acct-1", 1200, currency="EUR", idempotency_key="key-1")
        self.assertEqual(charge, Charge("ch_1", 1200, "EUR"))
        request = opener.requests[0]
        self.assertEqual(request.full_url, "https://pay.test/v3/charges")
        self.assertEqual(request.get_header("Idempotency-key"), "key-1")
        self.assertEqual(json.loads(request.data), {"account": "acct-1", "amount": 1200, "currency": "EUR"})

    def test_charge_rejects_unknown_currency(self):
        with self.assertRaises(ValueError):
            PaymentsAPI("https://pay.test", "k", opener=FakeOpener({})).charge(
                "acct-1", 100, currency="JPY", idempotency_key="key-1")

    def test_refund(self):
        opener = FakeOpener({"id": "re_1"})
        api = PaymentsAPI("https://pay.test", "k", opener=opener)
        self.assertEqual(api.refund("ch_1", 500, reason="duplicate"), "re_1")
        self.assertEqual(opener.requests[0].full_url, "https://pay.test/v3/charges/ch_1/refunds")
        self.assertIsNone(opener.requests[0].get_header("Idempotency-key"))

    def test_error_reply(self):
        with self.assertRaises(PaymentError):
            PaymentsAPI("https://pay.test", "k", opener=FakeOpener({"error": "card_declined"})).charge(
                "acct-1", 100, currency="EUR", idempotency_key="key-1")


if __name__ == "__main__":
    unittest.main()
