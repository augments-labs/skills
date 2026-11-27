import unittest

from app import client, http, metrics


class ApiTest(unittest.TestCase):
    def setUp(self):
        metrics.EVENTS.clear()

    def test_v1_invoice(self):
        self.assertEqual(client.get_invoice("inv-2"),
                         {"id": "inv-2", "customer": "globex", "amount": 19.99, "status": "open"})

    def test_v2_invoice(self):
        self.assertEqual(client.fetch_invoice("inv-1")["amount"], 37.5)

    def test_v1_total_is_counted(self):
        r = http.handle("GET", "/v1/total/inv-1", {"X-Client-Id": "partner-north"})
        self.assertEqual(r.body, {"total": 37.5})
        self.assertIn(("deprecated.call", 1, {"api": "GET /v1/total", "client": "partner-north"}),
                      metrics.EVENTS)
