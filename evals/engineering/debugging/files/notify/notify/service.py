class DeliveryError(RuntimeError):
    pass


class NotificationService:
    def __init__(self, gateway, users):
        self.gateway = gateway
        self.users = users

    def notify(self, user_id, text):
        """Send a routine notification. Muted users get nothing."""
        user = self.users.get(user_id)
        if user.muted:
            return None
        return self._check(self.gateway.send(user.email, text))

    def alert(self, user_id, text):
        """Send an alert. Alerts reach muted users too."""
        user = self.users.get(user_id)
        return self._check(self.gateway.send(user.email, text, priority="high"))

    @staticmethod
    def _check(receipt):
        if receipt.status != "queued":
            raise DeliveryError(f"message {receipt.id} was {receipt.status}")
        return receipt
