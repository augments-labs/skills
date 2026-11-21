from decimal import Decimal

from reports.orders import Order

ORDERS = [
    Order("acme", "EU", Decimal("120.00")),
    Order("acme", "EU", Decimal("80.00"), refunded=True),
    Order("acme", "US", Decimal("200.00")),
    Order("globex", "US", Decimal("1500.00")),
    Order("initech", "EU", Decimal("45.50")),
    Order("initech", "EU", Decimal("54.50")),
    Order("umbrella", "US", Decimal("300.00"), refunded=True),
    Order("umbrella", "US", Decimal("700.00")),
]
