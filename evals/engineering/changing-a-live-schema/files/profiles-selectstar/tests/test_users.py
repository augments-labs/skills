from app import users
from tests.helpers import DbTest


class UsersTest(DbTest):
    def test_create_then_get(self):
        uid = users.create_user(self.conn, "ada@example.com", "Ada Lovelace")
        self.assertEqual(
            users.get_user(self.conn, uid),
            {"id": uid, "email": "ada@example.com", "fullname": "Ada Lovelace"},
        )

    def test_rename(self):
        uid = users.create_user(self.conn, "ada@example.com", "Ada Lovelace")
        users.rename_user(self.conn, uid, "Ada King")
        self.assertEqual(users.get_user(self.conn, uid)["fullname"], "Ada King")

    def test_unknown_user(self):
        self.assertIsNone(users.get_user(self.conn, 999))
