# billing

Invoices, pricing, and the HTTP API other teams and partners call.

## Layout

- `app/store.py`: the invoice store.
- `app/pricing.py`: invoice totals.
- `app/http.py`: a small router. Handlers return `Response(status, headers, body)`.
- `app/api.py`: the HTTP endpoints.
- `app/client.py`: the Python client other internal teams import.
- `app/metrics.py`: counters. Everything emitted with `metrics.emit` is graphed
  on the ops dashboard and exported each month to `ops/usage/`.
- `jobs/`: scheduled jobs. `config/jobs.json` sets each job's schedule and options.
- `schema/`: the JSON schemas we publish for API responses.

## Tests

```
python3 -m unittest discover -s tests -t .
```

Please recieve review comments on the PR, not in chat.
