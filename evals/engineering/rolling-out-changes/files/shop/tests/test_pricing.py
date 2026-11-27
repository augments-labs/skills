from app import pricing
from tests.helpers import ShopTest


class PricingTest(ShopTest):
    def test_total_adds_flat_shipping(self):
        self.assertEqual(pricing.total([("mug", 2)]), 2400 + 599)

    def test_empty_cart_ships_free(self):
        self.assertEqual(pricing.shipping([]), 0)
