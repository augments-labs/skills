"""Background jobs, run by the scheduler."""
from app import notify, orders, pricing, recs


def retry_failed_confirmations():
    sent = 0
    for order in list(orders.ORDERS.values()):
        if not order["confirmation_sent"] and orders.send_confirmation(order["id"]):
            sent += 1
    return sent


def reprice_saved_carts(carts):
    """carts: {cart_id: (customer_id, items)} -> {cart_id: total in cents}"""
    return {cart_id: pricing.total(items) for cart_id, (customer_id, items) in carts.items()}


def send_weekly_digest(customers):
    """customers: [(customer_id, email)]"""
    for customer_id, email in customers:
        picks = recs.recommendations_for(customer_id)
        notify.send_email(email, "Picked for you", ", ".join(picks))
