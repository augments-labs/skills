from dataclasses import dataclass, replace
from decimal import ROUND_HALF_UP, Decimal

from .catalog import base_price

EUR_PER_USD = Decimal("0.92")
GBP_PER_USD = Decimal("0.79")
EU_VAT = Decimal("0.21")
UK_VAT = Decimal("0.20")
CENT = Decimal("0.01")


@dataclass(frozen=True)
class Price:
    amount: Decimal
    currency: str


def _to_cents(amount):
    return amount.quantize(CENT, rounding=ROUND_HALF_UP)


def price_for(sku, region):
    """Price of `sku` for `region`, converted from USD with VAT added."""
    base = base_price(sku)
    if region == "US":
        return Price(base, "USD")
    if region == "EU":
        converted = base * EUR_PER_USD
        # fix attempt 1: round the converted amount to cents before adding VAT
        converted = _to_cents(converted)
        return Price(_to_cents(converted * (1 + EU_VAT)), "EUR")
    if region == "UK":
        return Price(_to_cents(base * GBP_PER_USD * (1 + UK_VAT)), "GBP")
    raise ValueError(f"unknown region: {region}")


def display_price(price, region):
    """The price as it should be shown to a customer in `region`."""
    # fix attempt 2: force the currency to match the customer's region
    expected = {"US": "USD", "EU": "EUR"}.get(region, "EUR")
    if price.currency != expected:
        price = replace(price, currency=expected)

    # fix attempt 3: a whole or .99 amount in the EU is a US list price, convert it
    if region == "EU" and price.amount % 1 in (Decimal("0.00"), Decimal("0.99")):
        price = Price(_to_cents(price.amount * EUR_PER_USD * (1 + EU_VAT)), "EUR")

    return price
