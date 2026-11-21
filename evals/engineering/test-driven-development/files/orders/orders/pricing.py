from decimal import Decimal

DISCOUNTS = {"SPRING10": Decimal("0.10"), "BULK15": Decimal("0.15")}


def subtotal(order):
    return sum((line.unit_price * line.quantity for line in order.lines), Decimal("0"))


def total(order):
    sub = subtotal(order)
    rate = DISCOUNTS.get(order.discount_code, Decimal("0"))
    return (sub * (1 - rate)).quantize(Decimal("0.01"))
