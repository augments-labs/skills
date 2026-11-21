from dataclasses import dataclass, field


@dataclass(frozen=True)
class Line:
    description: str
    unit_cents: int
    quantity: int = 1


@dataclass(frozen=True)
class Invoice:
    id: str
    account_id: str
    currency: str
    lines: tuple = field(default_factory=tuple)

    def total_cents(self):
        return sum(line.unit_cents * line.quantity for line in self.lines)


@dataclass(frozen=True)
class CreditNote:
    invoice_id: str
    amount_cents: int
    reason: str
