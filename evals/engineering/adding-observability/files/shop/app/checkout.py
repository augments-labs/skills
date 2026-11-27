"""Checkout: charge the cart and place the order."""
from app import api, store

ORDERS = []


@api.route("/checkout")
def checkout(user_id, cart, gateway):
    """Charge `cart` for `user_id`. Raises PaymentDeclined or PaymentTimeout."""
    total = store.order_total(cart)
    receipt = gateway.charge(user_id, total)
    ORDERS.append({"user_id": user_id, "total_cents": total, "receipt": receipt})
    return {"status": "placed", "total_cents": total}
