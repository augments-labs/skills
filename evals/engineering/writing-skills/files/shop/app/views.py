"""Storefront page titles."""

TITLES = {
    "home": "Welcome to the shop",
    "cart": "Your cart",
    "checkout": "Checkout",
}


def title(page):
    return TITLES.get(page, "Shop")
