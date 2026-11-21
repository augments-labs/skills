import sqlite3
from dataclasses import dataclass


class UserNotFound(LookupError):
    pass


class DuplicateEmail(ValueError):
    pass


@dataclass(frozen=True)
class User:
    id: str
    email: str
    name: str
    active: bool = True


def normalize_email(email):
    return email.strip().lower()


class SqliteUserStore:
    """Users kept in SQLite.

    Emails are stored and matched normalized (surrounding whitespace removed,
    lower case), so an address belongs to at most one user, active or not.
    """

    def __init__(self, path=":memory:"):
        self.db = sqlite3.connect(path)
        self.db.execute("CREATE TABLE IF NOT EXISTS users ("
                        " n INTEGER PRIMARY KEY AUTOINCREMENT,"
                        " email TEXT UNIQUE NOT NULL,"
                        " name TEXT NOT NULL,"
                        " active INTEGER NOT NULL DEFAULT 1)")

    def add(self, email, name):
        """Store a new active user. Raises DuplicateEmail if the address is taken."""
        email = normalize_email(email)
        try:
            with self.db:
                cur = self.db.execute("INSERT INTO users (email, name) VALUES (?, ?)", (email, name))
        except sqlite3.IntegrityError:
            raise DuplicateEmail(email) from None
        return User(f"u-{cur.lastrowid}", email, name)

    def get(self, user_id):
        """Return the user with this id. Raises UserNotFound."""
        row = self.db.execute("SELECT n, email, name, active FROM users WHERE n = ?",
                              (self._number(user_id),)).fetchone()
        if row is None:
            raise UserNotFound(user_id)
        return self._user(row)

    def find_by_email(self, email):
        """Return the user with this address, or None."""
        row = self.db.execute("SELECT n, email, name, active FROM users WHERE email = ?",
                              (normalize_email(email),)).fetchone()
        return None if row is None else self._user(row)

    def deactivate(self, user_id):
        """Mark a user inactive and return it. Raises UserNotFound."""
        with self.db:
            cur = self.db.execute("UPDATE users SET active = 0 WHERE n = ?", (self._number(user_id),))
        if cur.rowcount == 0:
            raise UserNotFound(user_id)
        return self.get(user_id)

    def active_users(self):
        """Return the active users ordered by email."""
        rows = self.db.execute("SELECT n, email, name, active FROM users WHERE active = 1 ORDER BY email")
        return [self._user(row) for row in rows]

    @staticmethod
    def _number(user_id):
        prefix, _, number = str(user_id).partition("-")
        return int(number) if prefix == "u" and number.isdigit() else -1

    @staticmethod
    def _user(row):
        return User(f"u-{row[0]}", row[1], row[2], bool(row[3]))
