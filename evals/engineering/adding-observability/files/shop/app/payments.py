"""Card gateway client."""


class PaymentDeclined(Exception):
    pass


class PaymentTimeout(Exception):
    pass


class Gateway:
    """Talks to the card processor. Tests and staging pass a fake."""

    def charge(self, user_id, amount_cents):
        raise NotImplementedError
