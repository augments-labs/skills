from app import users
from tests.helpers import DbTest


class UsersTest(DbTest):
    def test_display_name_defaults_to_fullname(self):
        uid = users.create_user(self.conn, "ada@example.com", "Ada Lovelace")
        self.assertEqual(users.get_user(self.conn, uid)["display_name"], "Ada Lovelace")

    def test_picked_display_name(self):
        uid = users.create_user(self.conn, "ada@example.com", "Augusta Ada King")
        users.set_display_name(self.conn, uid, "Ada")
        user = users.get_user(self.conn, uid)
        self.assertEqual((user["fullname"], user["display_name"]), ("Augusta Ada King", "Ada"))

    def test_unknown_user(self):
        self.assertIsNone(users.get_user(self.conn, 999))
