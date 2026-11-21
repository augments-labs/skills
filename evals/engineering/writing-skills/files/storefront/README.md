# storefront

Order service for the shop: Postgres schema, the HTTP API, and the billing
plugin.

## Layout

- `storefront/`: the service code.
- `migrations/`: the core schema, one `NNNN_<slug>.up.sql` and one
  `NNNN_<slug>.down.sql` per migration.
- `plugins/<plugin>/migrations/`: each plugin's own schema, numbered
  separately from the core.
- `migrate.py`: the migration runner (`python3 migrate.py up`, `python3 migrate.py down N`).
- `docs/incidents.md`: postmortems.

## Tests

```bash
python3 -m unittest discover -s tests -t .
```
