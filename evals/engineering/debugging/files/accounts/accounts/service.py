from .store import DuplicateEmail, UserNotFound


class AlreadyRegistered(Exception):
    pass


class AccountService:
    def __init__(self, store):
        self.store = store

    def register(self, email, name):
        try:
            return self.store.add(email, name)
        except DuplicateEmail:
            raise AlreadyRegistered(email) from None

    def close(self, user_id):
        """Deactivate a member. Returns False when there is no such member."""
        try:
            self.store.deactivate(user_id)
        except UserNotFound:
            return False
        return True

    def lookup(self, email):
        return self.store.find_by_email(email)

    def mailing_list(self):
        return [user.email for user in self.store.active_users()]
