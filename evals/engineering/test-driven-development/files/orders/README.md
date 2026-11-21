# orders

Order intake for the wholesale shop: the order model, validation, and pricing.

- `orders/model.py`: `Order` and `Line`.
- `orders/validation.py`: `validate_order(order)` raises `ValidationError` for an
  order the warehouse must not accept.
- `orders/pricing.py`: subtotal, discount codes, and totals.

## Development

Every behavior change ships with unit tests under `tests/`. Shared test helpers
live in `tests/helpers.py`. Run the tests with:

```bash
python3 -m unittest discover -s tests -t .
```
