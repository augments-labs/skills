import unittest

from catalog.search import search


class SearchTest(unittest.TestCase):
    def test_matches_all_words(self):
        index = {"a": {"sku": "a", "title": "Blue garden hose", "published": True}}
        self.assertEqual([d["sku"] for d in search(index, "garden hose")], ["a"])

    def test_skips_unpublished(self):
        index = {"a": {"sku": "a", "title": "Hose", "published": False}}
        self.assertEqual(search(index, "hose"), [])


if __name__ == "__main__":
    unittest.main()
