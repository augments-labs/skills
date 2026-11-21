from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Product:
    sku: str
    name: str
    category: str
    price: Decimal
    in_stock: bool = True


def sample_products():
    """A small fixed catalog used by the dev server and the tests."""
    rows = [
        ("A-100", "Anchor bolt", "hardware", "0.40"),
        ("A-200", "Angle bracket", "hardware", "2.15"),
        ("B-100", "Bench vise", "tools", "54.00"),
        ("C-100", "Cable ties (100)", "electrical", "6.90"),
        ("C-200", "Circuit tester", "electrical", "18.50"),
        ("D-100", "Drill bit set", "tools", "24.99"),
        ("H-100", "Hex key set", "tools", "9.75"),
        ("W-100", "Wood glue", "adhesives", "5.25"),
    ]
    return [Product(sku, name, cat, Decimal(price)) for sku, name, cat, price in rows]
