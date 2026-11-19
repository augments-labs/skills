from decimal import Decimal

PRICES_USD = {
    "mug": Decimal("12.00"),
    "tee": Decimal("24.50"),
    "cap": Decimal("18.99"),
    "poster": Decimal("9.95"),
    "hoodie": Decimal("54.00"),
    "sticker": Decimal("1.20"),
    "lamp": Decimal("26.95"),
    "beanie": Decimal("21.30"),
}


class UnknownSku(KeyError):
    pass


def base_price(sku):
    """List price in US dollars."""
    try:
        return PRICES_USD[sku]
    except KeyError:
        raise UnknownSku(sku) from None


def skus():
    return sorted(PRICES_USD)
