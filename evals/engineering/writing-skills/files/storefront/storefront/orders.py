"""Order status transitions."""

STATUSES = ("pending", "paid", "shipped", "delivered", "cancelled", "refunded")

TRANSITIONS = {
    "pending": {"paid", "cancelled"},
    "paid": {"shipped", "refunded", "cancelled"},
    "shipped": {"delivered"},
    "delivered": {"refunded"},
    "cancelled": set(),
    "refunded": set(),
}


def can_move(current, new):
    return new in TRANSITIONS.get(current, set())
