import json
import urllib.request
from dataclasses import dataclass

PRIORITIES = ("low", "normal", "high")


class GatewayError(RuntimeError):
    pass


@dataclass(frozen=True)
class Receipt:
    id: str
    status: str


class Gateway:
    """Client for the messaging gateway's HTTP API."""

    def __init__(self, endpoint, token, timeout=10, opener=urllib.request.urlopen):
        self.endpoint = endpoint.rstrip("/")
        self.token = token
        self.timeout = timeout
        self._open = opener

    def send(self, recipient, body, *, priority="normal") -> Receipt:
        if priority not in PRIORITIES:
            raise ValueError(f"unknown priority: {priority}")
        payload = json.dumps({"to": recipient, "body": body, "priority": priority}).encode("utf-8")
        request = urllib.request.Request(
            self.endpoint + "/v2/messages",
            data=payload,
            method="POST",
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
        )
        with self._open(request, timeout=self.timeout) as response:
            data = json.load(response)
        if "id" not in data:
            raise GatewayError(data.get("error", "no message id in response"))
        return Receipt(id=str(data["id"]), status=data["status"])
