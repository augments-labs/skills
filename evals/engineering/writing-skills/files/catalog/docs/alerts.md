# Catalog alerts

| Alert | Meaning | Runbook |
|---|---|---|
| `catalog_search_drift_high` | Sampled drift between the database and the search index above 2% for 15 minutes | `docs/runbooks/lamplight.md` |
| `catalog_search_p95_high` | Search p95 latency above 250 ms for 10 minutes | `docs/runbooks/search-latency.md` |
| `catalog_importer_backlog` | Supplier feed queue older than 30 minutes | ask #catalog |
