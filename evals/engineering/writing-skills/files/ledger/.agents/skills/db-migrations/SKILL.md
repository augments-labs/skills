---
name: db-migration
description: Use when adding or editing a database migration in this repo.
  Covers numbering, down files, and the transaction header (format: `-- migrate: no-transaction`).
---

# Database migrations

1. Take the next free number in `migrations/`. Read
   `references/numbering.md` if two branches may have taken the same number.
2. Write both `NNNN_<slug>.up.sql` and `NNNN_<slug>.down.sql`. A migration
   without a down file cannot be rolled back.
3. A statement that cannot run in a transaction (`CREATE INDEX CONCURRENTLY`,
   `ALTER TYPE ... ADD VALUE`) needs `-- migrate: no-transaction` as the
   file's first line, or the runner wraps it in a transaction and the deploy
   fails.
4. Keep the migration backwards compatible: the previous release runs against
   the new schema until the deploy finishes.
