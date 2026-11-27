"""Weekly reminders for open invoices."""
from app import store


def run():
    return [inv["id"] for inv in store.INVOICES.values() if inv["status"] == "open"]
