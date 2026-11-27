import unittest

from app.export import export_csv, old_export

ORDERS = [
    {"id": "o1", "status": "paid", "amount_cents": 100},
    {"id": "o2", "status": "open", "amount_cents": 200},
    {"id": "o3", "status": "paid", "amount_cents": 300, "currency": "EUR"},
]


class ExportTest(unittest.TestCase):
    def test_header(self):
        self.assertEqual(export_csv(ORDERS).splitlines()[0], "id,amount_cents,currency")

    def test_rows(self):
        self.assertEqual(export_csv(ORDERS).splitlines()[1:], ["o1,100,USD", "o3,300,EUR"])

    def test_old_export(self):
        self.assertEqual(old_export(ORDERS), "o1,100\no3,300\n")


if __name__ == "__main__":
    unittest.main()
