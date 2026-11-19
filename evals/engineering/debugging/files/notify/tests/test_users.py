import unittest

from notify import User, UserDirectory


class UserDirectoryTests(unittest.TestCase):
    def test_get(self):
        users = UserDirectory([User("u-1", "ada@example.com")])
        self.assertEqual(users.get("u-1").email, "ada@example.com")

    def test_unknown_user(self):
        with self.assertRaises(KeyError):
            UserDirectory().get("u-1")


if __name__ == "__main__":
    unittest.main()
