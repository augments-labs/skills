# catalog

Product catalog service: the admin API, the supplier feed importer hooks, and
product search. Search reads the `catalog-live` index alias, not the database.

    python3 -m unittest discover -s tests -t .

Runbooks live in `docs/runbooks/`. Alerts are listed in `docs/alerts.md`.
