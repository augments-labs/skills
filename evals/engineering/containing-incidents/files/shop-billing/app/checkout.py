"""Checkout totals."""
from app import tax


def total_cents(items, region, discount_pct=0):
    """items: list of (unit_cents, qty). discount_pct applies to the subtotal."""
    subtotal = sum(unit * qty for unit, qty in items)
    taxed = subtotal + tax.tax_cents(subtotal, region)
    return round(taxed * (100 - discount_pct) / 100)
