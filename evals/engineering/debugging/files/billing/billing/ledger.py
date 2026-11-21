class Ledger:
    """Maps each invoice to the charge that paid it."""

    def __init__(self):
        self._charges = {}

    def record(self, invoice_id, charge_id):
        self._charges[invoice_id] = charge_id

    def charge_for(self, invoice_id):
        try:
            return self._charges[invoice_id]
        except KeyError:
            raise KeyError(f"no charge recorded for invoice {invoice_id}") from None
