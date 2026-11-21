import json
import urllib.request
from dataclasses import dataclass

CURRENCIES = ("EUR", "GBP", "USD")


class PaymentError(RuntimeError):
    pass


@dataclass(frozen=True)
class Charge:
    id: str
    amount_cents: int
    currency: str


class PaymentsAPI:
    """Client for the payments provider's HTTP API."""

    def __init__(self, endpoint, key, timeout=10, opener=urllib.request.urlopen):
        self.endpoint = endpoint.rstrip("/")
        self.key = key
        self.timeout = timeout
        self._open = opener

    def charge(self, account_id, amount_cents, *, currency, idempotency_key) -> Charge:
        """Charge an account.

        The provider returns the original charge for a repeated
        idempotency_key instead of charging again, so a retried run must send
        the same key for the same invoice.
        """
        if currency not in CURRENCIES:
            raise ValueError(f"unsupported currency: {currency}")
        if amount_cents <= 0:
            raise ValueError("amount_cents must be positive")
        data = self._post("/v3/charges", {"account": account_id, "amount": amount_cents,
                                          "currency": currency}, idempotency_key)
        return Charge(id=data["id"], amount_cents=data["amount"], currency=data["currency"])

    def refund(self, charge_id, amount_cents, *, reason) -> str:
        """Refund part or all of a charge. Returns the refund id."""
        if amount_cents <= 0:
            raise ValueError("amount_cents must be positive")
        data = self._post(f"/v3/charges/{charge_id}/refunds",
                          {"amount": amount_cents, "reason": reason}, None)
        return data["id"]

    def _post(self, path, payload, idempotency_key):
        headers = {"Authorization": f"Bearer {self.key}", "Content-Type": "application/json"}
        if idempotency_key is not None:
            headers["Idempotency-Key"] = idempotency_key
        request = urllib.request.Request(self.endpoint + path, data=json.dumps(payload).encode("utf-8"),
                                         method="POST", headers=headers)
        with self._open(request, timeout=self.timeout) as response:
            data = json.load(response)
        if "error" in data:
            raise PaymentError(data["error"])
        return data
