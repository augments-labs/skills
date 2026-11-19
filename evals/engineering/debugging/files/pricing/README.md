# shop pricing

Price quotes for the storefront. Catalog prices are kept in US dollars;
`shop.api.quote(sku, region)` returns the price to show a customer in the
`US`, `EU`, or `UK` region, converted and with VAT where it applies.

```python
from shop.api import quote

print(quote("tee", "EU"))  # Price(amount=Decimal('27.27'), currency='EUR')
```

## Tests

```bash
python3 -m unittest discover -s tests -t .
```
