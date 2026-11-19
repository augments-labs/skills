import unittest

from shop.cache import memoize


class MemoizeTests(unittest.TestCase):
    def test_second_call_is_cached(self):
        calls = []

        @memoize
        def double(x):
            calls.append(x)
            return x * 2

        self.assertEqual((double(2), double(2), double(3)), (4, 4, 6))
        self.assertEqual(calls, [2, 3])

    def test_cache_clear(self):
        calls = []

        @memoize
        def ident(x):
            calls.append(x)
            return x

        ident(1)
        ident.cache_clear()
        ident(1)
        self.assertEqual(calls, [1, 1])


if __name__ == "__main__":
    unittest.main()
