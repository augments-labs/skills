# billing

Monthly invoicing. `InvoiceRunner.run()` charges every invoice with a positive
total through the payments provider and records each charge in the ledger;
`InvoiceRunner.credit()` refunds a credit note against the charge of the
invoice it corrects.

```python
from billing import InvoiceRunner, Ledger, PaymentsAPI

runner = InvoiceRunner(PaymentsAPI("https://payments.internal", key="..."), Ledger())
runner.run(invoices)
```

## Tests

```bash
python3 -m unittest discover -s tests -t .
```
