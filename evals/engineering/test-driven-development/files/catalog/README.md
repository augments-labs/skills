# catalog

Product catalog service: an in-memory store, listing and filtering, and a
small HTTP-style handler layer used by the storefornt.

## Layout

- `catalog/store.py`: the `Product` record and the sample store.
- `catalog/listing.py`: `list_products`, filtering and sorting.
- `catalog/api.py`: request handlers (`handle_list_products`).

## Development

Every behavior change ships with unit tests under `tests/`. Run them with:

```bash
python3 -m unittest discover -s tests -t .
```
