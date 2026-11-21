import unittest

from reports.summary import summarize


class SummarizeTest(unittest.TestCase):
    def test_basic_month(self):
        orders = [
            {"id": "1", "customer": "Acme", "status": "paid", "amount": "100.00"},
            {"id": "2", "customer": "Birch", "status": "paid", "amount": "40.00"},
            {"id": "3", "customer": "Acme", "status": "paid", "amount": "10.00"},
        ]
        self.assertEqual(summarize(orders), {
            "orders": 3, "total": "150.00", "average": "50.00",
            "top_customers": [["Acme", "110.00"], ["Birch", "40.00"]],
        })

    def test_cancelled_orders_are_skipped(self):
        orders = [
            {"id": "1", "customer": "Acme", "status": "paid", "amount": "20.00"},
            {"id": "2", "customer": "Acme", "status": "cancelled", "amount": "99.00"},
        ]
        self.assertEqual(summarize(orders)["total"], "20.00")
