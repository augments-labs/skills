import unittest

from storefront.orders import can_move


class TransitionTest(unittest.TestCase):
    def test_paid_can_ship(self):
        self.assertTrue(can_move("paid", "shipped"))

    def test_cancelled_is_final(self):
        self.assertFalse(can_move("cancelled", "paid"))


if __name__ == "__main__":
    unittest.main()
