import unittest

from reports.export import summary_csv


class ExportTest(unittest.TestCase):
    def test_csv(self):
        orders = [{"id": "1", "customer": "Acme", "status": "paid", "amount": "12.50"}]
        self.assertEqual(summary_csv(orders), "orders,1\ntotal,12.50\naverage,12.50\ntop1,Acme,12.50\n")
