"""Orders and carts."""


def order_total(order):
    return sum(line["price_cents"] for line in order["lines"])
