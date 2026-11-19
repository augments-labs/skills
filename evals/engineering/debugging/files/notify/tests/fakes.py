class FakeGateway:
    """Records messages instead of calling the gateway."""

    def __init__(self):
        self.sent = []

    def send(self, to, body):
        self.sent.append((to, body))
        return {"status": "queued"}
