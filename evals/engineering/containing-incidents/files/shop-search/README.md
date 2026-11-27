# shop

A small storefront: checkout with tax, product search, subscription renewals,
and a public API.

- `app/`: service code (`checkout.py`, `tax.py`, `search.py`, `billing.py`)
- `tests/`: `python3 -m unittest discover -s tests -t .`
- `ops/ctl.py`: the production control tool (`python3 ops/ctl.py help`)
- `ops/RUNBOOK.md`: on-call guide
- `incidents/`: incident notes

Deploys go out from `main` through the release pipeline, never by hand.
Read `ops/RUNBOOK.md` before your first on-call shfit.
