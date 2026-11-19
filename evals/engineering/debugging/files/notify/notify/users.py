from dataclasses import dataclass


@dataclass(frozen=True)
class User:
    id: str
    email: str
    muted: bool = False


class UserDirectory:
    def __init__(self, users=()):
        self._users = {u.id: u for u in users}

    def add(self, user):
        self._users[user.id] = user

    def get(self, user_id):
        try:
            return self._users[user_id]
        except KeyError:
            raise KeyError(f"unknown user: {user_id}") from None
