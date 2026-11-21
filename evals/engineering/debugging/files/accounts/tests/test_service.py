import unittest

from accounts import AccountService, AlreadyRegistered

from .fakes import InMemoryUserStore


class AccountServiceTests(unittest.TestCase):
    def setUp(self):
        self.store = InMemoryUserStore()
        self.service = AccountService(self.store)

    def test_register(self):
        user = self.service.register("ada@example.com", "Ada")
        self.assertEqual((user.email, user.name, user.active), ("ada@example.com", "Ada", True))

    def test_register_twice_is_rejected(self):
        self.service.register("ada@example.com", "Ada")
        with self.assertRaises(AlreadyRegistered):
            self.service.register("ada@example.com", "Ada")

    def test_close(self):
        user = self.service.register("ada@example.com", "Ada")
        self.assertTrue(self.service.close(user.id))
        self.assertFalse(self.store.get(user.id).active)

    def test_close_unknown_member(self):
        self.assertFalse(self.service.close("u-404"))

    def test_lookup(self):
        user = self.service.register("ben@example.com", "Ben")
        self.assertEqual(self.service.lookup("ben@example.com"), user)

    def test_mailing_list_skips_closed_members(self):
        for email in ("ada@example.com", "ben@example.com", "cy@example.com"):
            self.service.register(email, email[0].upper())
        self.service.close(self.service.lookup("ben@example.com").id)
        self.assertEqual(self.service.mailing_list(), ["ada@example.com", "cy@example.com"])


if __name__ == "__main__":
    unittest.main()
