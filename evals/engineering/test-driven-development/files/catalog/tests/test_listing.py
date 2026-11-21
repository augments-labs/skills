import unittest
from decimal import Decimal

from catalog.listing import list_products
from catalog.store import Product, sample_products


class ListProductsTest(unittest.TestCase):
    def test_sorts_by_name_by_default(self):
        names = [p.name for p in list_products(sample_products())]
        self.assertEqual(names, sorted(names, key=str.lower))

    def test_filters_by_category(self):
        rows = list_products(sample_products(), category="tools")
        self.assertEqual({p.sku for p in rows}, {"B-100", "D-100", "H-100"})

    def test_in_stock_only(self):
        rows = [Product("X-1", "x", "misc", Decimal("1"), in_stock=False),
                Product("Y-1", "y", "misc", Decimal("1"))]
        self.assertEqual([p.sku for p in list_products(rows, in_stock_only=True)], ["Y-1"])

    def test_unknown_sort_key(self):
        with self.assertRaises(ValueError):
            list_products(sample_products(), sort="colour")


if __name__ == "__main__":
    unittest.main()
