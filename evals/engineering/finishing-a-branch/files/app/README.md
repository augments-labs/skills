# orders-export

Exports paid orders as CSV for the warehouse.

```python
from app.export import export_csv, old_export
```

`old_export(orders)` is kept for the billing team's scripts, which still
recieve the old two-column format.

Run the tests with `python3 -m unittest discover -s tests -t .`.
