import unittest

from notify import NotificationService, User, UserDirectory
from tests.fakes import FakeGateway


class AlertTests(unittest.TestCase):
    def setUp(self):
        self.gateway = FakeGateway()
        users = UserDirectory([User("u-1", "ada@example.com"), User("u-2", "ben@example.com", muted=True)])
        self.service = NotificationService(self.gateway, users)

    def test_alert_reaches_user(self):
        self.service.alert("u-1", "Disk almost full")
        self.assertEqual(self.gateway.sent, [("ada@example.com", "Disk almost full")])

    def test_alert_reaches_muted_user(self):
        self.service.alert("u-2", "Password changed")
        self.assertEqual(self.gateway.sent, [("ben@example.com", "Password changed")])

    def test_alert_returns_receipt(self):
        receipt = self.service.alert("u-1", "Disk almost full")
        self.assertEqual(receipt.status, "queued")

    def test_unknown_user(self):
        with self.assertRaises(KeyError):
            self.service.alert("u-9", "hello")
        self.assertEqual(self.gateway.sent, [])


if __name__ == "__main__":
    unittest.main()
