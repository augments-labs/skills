"""Request handlers. Each returns the JSON body as a dict."""
from app import cache, orders, pricing, recs


def handle_quote(customer_id, cart_id, items):
    key = f"quote:{cart_id}"
    cached = cache.get(key)
    if cached is not None:
        return {"cart_id": cart_id, "total": cached}
    # Fast path: quotes skip the full order build and add flat shipping directly.
    total = pricing.subtotal(items) + (pricing.FLAT_SHIPPING if items else 0)
    cache.set(key, total)
    return {"cart_id": cart_id, "total": total}


def handle_checkout(customer_id, email, items, ship_to):
    order = orders.place_order(customer_id, email, items, ship_to)
    return {
        "order_id": order["id"],
        "total": order["total"],
        "recommended": recs.recommendations_for(customer_id),
    }
