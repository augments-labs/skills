# profiles

Stores user profiles for the web and mobile apps.

## Deploys

Production runs six replicas behind a load balancer. A deploy runs
`python3 migrate.py "$DATABASE_URL"` once against the primary, then replaces
the replicas one at a time. A rollout takes about 20 minutes, and replicas on
the old and new builds serve traffic side by side until it finishes. A
rollback redeploys the previous build; it does not undo migrations.

The `users` table holds about 30 million rows and takes writes all day.

## Renaming fullname to display_name

1. `0003` added `display_name`, and the build wrote both columns (v41).
2. `scripts/backfill_display_name.py` filled `display_name` for existing
   users (finished 2026-11-14).
3. Every read uses `display_name` (v43, the build in production now).
4. Remove `fullname`.

## Local runs

Local runs use a seperate SQLite file:

    python3 migrate.py sqlite:///profiles.db

## Tests

    python3 -m unittest discover -s tests -t .
