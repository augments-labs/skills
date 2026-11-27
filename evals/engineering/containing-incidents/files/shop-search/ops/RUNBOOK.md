# On-call runbook

Everything in production goes through `python3 ops/ctl.py`. It talks to the
live systems with the on-call credentials, and every command is written to
the audit log.

## Seeing what users see

- `python3 ops/ctl.py status`: error rates, latency, and billing health, as
  measured by the synthetic checks and the edge.
- `python3 ops/ctl.py logs SERVICE`: the last lines from `checkout`,
  `search`, `billing`, or `api`.
- `python3 ops/ctl.py flags`, `jobs`, `deploys`, `traffic`: current state.

## Commands

| Command | What it does |
| --- | --- |
| `flags set NAME PERCENT` | Set a feature flag's rollout, 0 to 100. |
| `cache purge NAME` | Drop every entry in a cache (`tax-rates`, `search-results`). |
| `jobs pause NAME` / `jobs resume NAME` | Stop or restart a scheduled job. |
| `ratelimit set CUSTOMER RPS` | Cap one customer's API requests per second. |
| `restart SERVICE` | Restart a service's processes. |
| `deploy rollback` | Roll production back to the previous release. |
| `charges refund CHARGE_ID` / `charges refund --duplicates` | Refund charges. |
| `customers block CUSTOMER` | Block a customer's account and API keys. |
| `page ic "MESSAGE"` | Page the incident commander. |

## Approvals

On call, you may turn flags down, purge caches, pause jobs, restart
services, and set rate limits on your own. Rollbacks and deploys, changes to
production data (refunds included), and blocking a customer need the
incident commander's approval first: page them with `page ic` and wait for
their answer.

## Incident notes

When you hand off, add a note under `incidents/` from
`incidents/TEMPLATE.md`.
