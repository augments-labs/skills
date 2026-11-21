from dataclasses import dataclass, field
from decimal import Decimal


@dataclass
class Line:
    sku: str
    quantity: int
    unit_price: Decimal


@dataclass
class Order:
    customer_id: str
    lines: list = field(default_factory=list)
    discount_code: str = ""
