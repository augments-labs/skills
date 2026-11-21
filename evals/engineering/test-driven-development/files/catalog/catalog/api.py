"""Request handlers. A handler takes the query parameters as a dict of strings
and returns (status, body)."""
from .listing import list_products
from .store import sample_products


def _product_json(p):
    return {"sku": p.sku, "name": p.name, "category": p.category,
            "price": str(p.price), "in_stock": p.in_stock}


def handle_list_products(query, products=None):
    """GET /products?category=...&in_stock=1&sort=name|price|sku"""
    products = sample_products() if products is None else products
    try:
        rows = list_products(
            products,
            category=query.get("category") or None,
            in_stock_only=query.get("in_stock") == "1",
            sort=query.get("sort", "name"),
        )
    except ValueError as exc:
        return 400, {"error": str(exc)}
    return 200, {"products": [_product_json(p) for p in rows]}
