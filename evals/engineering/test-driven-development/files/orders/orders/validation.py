from .pricing import DISCOUNTS


class ValidationError(ValueError):
    pass


def validate_order(order):
    """Raise ValidationError if the warehouse must not accept `order`."""
    if not order.customer_id:
        raise ValidationError("order has no customer")
    if not order.lines:
        raise ValidationError("order has no lines")
    for line in order.lines:
        if line.quantity <= 0:
            raise ValidationError(f"{line.sku}: quantity must be positive")
        if line.unit_price < 0:
            raise ValidationError(f"{line.sku}: negative unit price")
    if order.discount_code and order.discount_code not in DISCOUNTS:
        raise ValidationError(f"unknown discount code {order.discount_code!r}")
