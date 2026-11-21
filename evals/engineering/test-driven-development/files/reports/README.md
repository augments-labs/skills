# reports

Monthly order reports for finance. `reports.summary.summarize(orders)` builds the
summary that the finance export writes out; `reports.export` turns it into the
CSV finance imports.

An order is a dict: `{"id": str, "customer": str, "status": str, "amount": str}`.
Amounts are decimal strings in the shop currency.

## Development

Every behavior change ships with unit tests under `tests/`. Run them with:

```bash
python3 -m unittest discover -s tests -t .
```
