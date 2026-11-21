"""Listing products: filter, then sort."""

SORT_KEYS = {
    "name": lambda p: p.name.lower(),
    "price": lambda p: (p.price, p.name.lower()),
    "sku": lambda p: p.sku,
}


def list_products(products, *, category=None, in_stock_only=False, sort="name"):
    """Return the products that match the filters, sorted by `sort`.

    Raises ValueError for an unknown sort key.
    """
    if sort not in SORT_KEYS:
        raise ValueError(f"unknown sort key: {sort!r}")
    rows = [p for p in products
            if (category is None or p.category == category)
            and (not in_stock_only or p.in_stock)]
    return sorted(rows, key=SORT_KEYS[sort])
