import io
import json
import unittest

from notify import Gateway, GatewayError, Receipt


class FakeOpener:
    def __init__(self, reply):
        self.reply = reply
        self.requests = []

    def __call__(self, request, timeout):
        self.requests.append(request)
        return io.BytesIO(json.dumps(self.reply).encode("utf-8"))


class GatewayTests(unittest.TestCase):
    def test_send_posts_message(self):
        opener = FakeOpener({"id": 41, "status": "queued"})
        receipt = Gateway("https://gw.test/", "t0k", opener=opener).send("ada@example.com", "hi")
        self.assertEqual(receipt, Receipt(id="41", status="queued"))
        request = opener.requests[0]
        self.assertEqual(request.full_url, "https://gw.test/v2/messages")
        self.assertEqual(json.loads(request.data),
                         {"to": "ada@example.com", "body": "hi", "priority": "normal"})

    def test_priority_is_sent(self):
        opener = FakeOpener({"id": 42, "status": "queued"})
        Gateway("https://gw.test", "t0k", opener=opener).send("a@example.com", "hi", priority="high")
        self.assertEqual(json.loads(opener.requests[0].data)["priority"], "high")

    def test_unknown_priority(self):
        with self.assertRaises(ValueError):
            Gateway("https://gw.test", "t0k", opener=FakeOpener({})).send("a@example.com", "hi", priority="urgent")

    def test_error_reply(self):
        with self.assertRaises(GatewayError):
            Gateway("https://gw.test", "t0k", opener=FakeOpener({"error": "quota"})).send("a@example.com", "hi")


if __name__ == "__main__":
    unittest.main()
