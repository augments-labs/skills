from app import address, metrics, notify, pricing

ORDERS = {}


def place_order(customer_id, email, items, ship_to):
    if not items:
        raise ValueError("empty order")
    try:
        address.validate(ship_to)
    except address.AddressError:
        metrics.emit("checkout.failed", reason="address")
        raise
    order_id = len(ORDERS) + 1
    ORDERS[order_id] = {
        "id": order_id,
        "customer_id": customer_id,
        "email": email,
        "items": list(items),
        "total": pricing.total(items),
        "confirmation_sent": False,
    }
    metrics.emit("checkout.completed")
    send_confirmation(order_id)
    return ORDERS[order_id]


def send_confirmation(order_id):
    order = ORDERS[order_id]
    try:
        notify.send_email(order["email"], f"Order {order_id} confirmed",
                          f"Thanks! Your total is ${order['total'] / 100:.2f}.")
    except notify.SendError:
        metrics.emit("confirmation.failed")
        return False
    order["confirmation_sent"] = True
    return True
