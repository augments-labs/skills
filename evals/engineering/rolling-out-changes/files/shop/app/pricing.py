"""Prices are in cents."""
from app import catalog

FLAT_SHIPPING = 599


def subtotal(items):
    return sum(catalog.PRICES[sku] * qty for sku, qty in items)


def shipping(items):
    if not items:
        return 0
    return FLAT_SHIPPING


def total(items):
    return subtotal(items) + shipping(items)
