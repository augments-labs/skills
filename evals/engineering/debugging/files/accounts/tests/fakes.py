from dataclasses import replace

from accounts.store import User


class InMemoryUserStore:
    """In-memory stand-in for SqliteUserStore, for fast service tests."""

    def __init__(self):
        self.users = {}

    def add(self, email, name):
        user = User(f"u-{len(self.users) + 1}", email, name)
        self.users[user.id] = user
        return user

    def get(self, user_id):
        return self.users.get(user_id)

    def find_by_email(self, email):
        for user in self.users.values():
            if user.email == email:
                return user
        return None

    def deactivate(self, user_id):
        user = replace(self.get(user_id), active=False)
        self.users[user_id] = user
        return user

    def active_users(self):
        return [user for user in self.users.values() if user.active]
