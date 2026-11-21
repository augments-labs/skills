import unittest
from unittest.mock import Mock

from billing import Charge, CreditNote, Invoice, InvoiceRunner, Ledger, Line


def invoice(id, *lines, account="acct-1", currency="EUR"):
    return Invoice(id, account, currency, tuple(lines))


class InvoiceRunnerTests(unittest.TestCase):
    def setUp(self):
        self.api = Mock()
        self.ledger = Ledger()
        self.runner = InvoiceRunner(self.api, self.ledger)

    def test_charges_each_invoice(self):
        self.api.charge.side_effect = [Charge("ch_1", 1200, "EUR"), Charge("ch_2", 300, "EUR")]
        results = self.runner.run([invoice("inv-1", Line("seat", 600, 2)), invoice("inv-2", Line("addon", 300))])
        self.assertEqual(results, [("inv-1", "ch_1"), ("inv-2", "ch_2")])
        self.assertEqual(self.api.charge.call_count, 2)

    def test_records_charge_in_ledger(self):
        self.api.charge.return_value = Charge("ch_9", 600, "EUR")
        self.runner.run([invoice("inv-1", Line("seat", 600))])
        self.assertEqual(self.ledger.charge_for("inv-1"), "ch_9")

    def test_skips_empty_invoice(self):
        results = self.runner.run([invoice("inv-0")])
        self.assertEqual(results, [("inv-0", "skipped")])
        self.api.charge.assert_not_called()

    def test_credit_refunds_original_charge(self):
        self.ledger.record("inv-1", "ch_1")
        self.api.refund.return_value = "re_1"
        refund_id = self.runner.credit(CreditNote("inv-1", 500, "duplicate seat"))
        self.assertEqual(refund_id, "re_1")
        self.assertEqual(self.api.refund.call_args.args[0], "ch_1")

    def test_credit_without_charge(self):
        with self.assertRaises(KeyError):
            self.runner.credit(CreditNote("inv-404", 500, "typo"))


if __name__ == "__main__":
    unittest.main()
