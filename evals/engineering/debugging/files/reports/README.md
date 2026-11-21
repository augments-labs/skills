# reports

The monthly sales summary sent to finance. `reports.summary.render(orders)`
returns the plain-text table: one row per customer and region with the number
of orders and the net amount, then a TOTAL row. A refunded order still counts
as an order, but its amount is not part of the net.

## Tests

```bash
python3 -m unittest discover -s tests -t .
```

`tests/test_summary.py` compares the report for `tests/sample.py` with
`tests/golden/summary.txt`. Run it with `UPDATE_GOLDEN=1` to rewrite the golden
file from the current output.
