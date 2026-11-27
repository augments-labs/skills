"""Subscription renewals."""


def due(subscriptions, today):
    return [s["id"] for s in subscriptions if s["renews_on"] == today and s["active"]]
