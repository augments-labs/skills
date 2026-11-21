class InvoiceRunner:
    def __init__(self, api, ledger):
        self.api = api
        self.ledger = ledger

    def run(self, invoices):
        """Charge every invoice with a positive total. Returns (invoice id, charge id or 'skipped')."""
        results = []
        for invoice in invoices:
            total = invoice.total_cents()
            if total <= 0:
                results.append((invoice.id, "skipped"))
                continue
            charge = self.api.charge(invoice.account_id, total, currency=invoice.currency)
            self.ledger.record(invoice.id, charge.id)
            results.append((invoice.id, charge.id))
        return results

    def credit(self, note):
        """Refund a credit note against the charge that paid its invoice."""
        charge_id = self.ledger.charge_for(note.invoice_id)
        return self.api.refund(charge_id, note.amount_cents, note.reason)
