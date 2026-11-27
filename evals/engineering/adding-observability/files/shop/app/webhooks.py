"""Payment processor webhooks."""
import hashlib
import hmac

from app import api

SECRET = b"whsec_test_only"
SEEN = set()
PAID = []


class WebhookError(Exception):
    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


def sign(event_id, secret=SECRET):
    return hmac.new(secret, event_id.encode(), hashlib.sha256).hexdigest()


def _paid(event):
    PAID.append(event["order_id"])


HANDLERS = {"payment.succeeded": _paid}


@api.route("/webhooks/payments")
def handle(event):
    if not hmac.compare_digest(event.get("signature", ""), sign(event["id"])):
        raise WebhookError("bad_signature")
    if event["type"] not in HANDLERS:
        raise WebhookError("unknown_event")
    if event["id"] in SEEN:
        raise WebhookError("duplicate")
    SEEN.add(event["id"])
    HANDLERS[event["type"]](event)
    return {"ok": True}
