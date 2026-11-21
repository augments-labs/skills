import unittest

from catalog.api import handle_list_products


class HandleListProductsTest(unittest.TestCase):
    def test_lists_products(self):
        status, body = handle_list_products({})
        self.assertEqual(status, 200)
        self.assertEqual(len(body["products"]), 8)

    def test_bad_sort_is_400(self):
        status, body = handle_list_products({"sort": "colour"})
        self.assertEqual(status, 400)
        self.assertIn("colour", body["error"])


if __name__ == "__main__":
    unittest.main()
