# ledger

Account activity for the billing API, on PostgreSQL 16.

- `events` holds about 900 million rows and takes about 4,000 inserts a
  second.
- `accounts` is read on every API request. The nightly reconciliation job
  holds long read transactions on `accounts` and `events`.

## Deploys

A deploy runs `python3 migrate.py "$DATABASE_URL"` once against the primary,
then rolls out the new build.

## Tests

    python3 -m unittest discover -s tests -t .
