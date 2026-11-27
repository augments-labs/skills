# shop

The storefront service and its batch jobs.

- `app/`: the service (`main.py` builds it; `api.py`, `checkout.py`,
  `search.py`, `webhooks.py`, `store.py`)
- `jobs/`: batch jobs run by cron (`python3 -m jobs.nightly_export`)
- `obs/`: metrics helpers; see `obs/README.md`
- `ops/alerts.json`: alert rules
- `tests/`: `python3 -m unittest discover -s tests -t .`

Prometheus scrapes the service evrey 15 seconds.
