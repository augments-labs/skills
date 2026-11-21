from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Order:
    customer: str
    region: str
    amount: Decimal
    refunded: bool = False
