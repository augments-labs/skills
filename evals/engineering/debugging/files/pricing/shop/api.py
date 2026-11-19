from .cache import memoize
from .pricing import display_price, price_for


@memoize
def _regional_price(sku, region):
    return price_for(sku, region)


def quote(sku, region):
    """Price a SKU for a customer's region, ready to display."""
    return display_price(_regional_price(sku, region), region)


def clear_cache():
    _regional_price.cache_clear()
