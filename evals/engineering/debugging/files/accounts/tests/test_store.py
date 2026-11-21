import unittest

from accounts import DuplicateEmail, SqliteUserStore, User, UserNotFound


class SqliteUserStoreTests(unittest.TestCase):
    def setUp(self):
        self.store = SqliteUserStore()

    def test_add_and_get(self):
        user = self.store.add("ada@example.com", "Ada")
        self.assertEqual(user, User("u-1", "ada@example.com", "Ada"))
        self.assertEqual(self.store.get("u-1"), user)

    def test_get_unknown(self):
        with self.assertRaises(UserNotFound):
            self.store.get("u-9")

    def test_duplicate_email(self):
        self.store.add("ada@example.com", "Ada")
        with self.assertRaises(DuplicateEmail):
            self.store.add("ada@example.com", "Ada Again")

    def test_find_by_email(self):
        user = self.store.add("ada@example.com", "Ada")
        self.assertEqual(self.store.find_by_email("ada@example.com"), user)
        self.assertIsNone(self.store.find_by_email("ben@example.com"))

    def test_deactivate(self):
        user = self.store.add("ada@example.com", "Ada")
        self.assertFalse(self.store.deactivate(user.id).active)
        self.assertEqual(self.store.active_users(), [])


if __name__ == "__main__":
    unittest.main()
