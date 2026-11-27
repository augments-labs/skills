# Changing a live schema

The `changing-a-live-schema` skill makes your agent treat a migration as something that runs while the build now in production is still serving. A change that works for the new code alone, but breaks the old build during the rollout or after a rollback, does not count as done.

## When it loads (and when it skips)

`changing-a-live-schema` loads before the first edit when a task adds, renames, retypes, or removes a column, table, index, or constraint, writes a backfill or data migration, or adds a migration file for a database that serves production. It loads even when the change looks like a single `ALTER` statement.

It skips:

- A database nothing serves yet, such as a brand-new project or a test-only database.
- Questions and explanations that change nothing.
- Code changes that touch no schema, such as renaming a Python function or adding type hints.

## What the agent does differently

1. **Reads how deploys and migrations run first.** Before editing, the agent checks when migrations apply relative to the rollout, whether old and new builds serve side by side, whether the runner wraps each file in a transaction or sets a lock timeout, and who reads or writes the table in the build now in production.
2. **Splits renames and removals across deploys.** A rename becomes expand, write both, backfill, switch reads, stop writing, and contract. Adding the new column and writing to both columns ship together as the first deploy. The agent does that deploy now, keeps the old column as the source of truth for reads, and reports what each later deploy waits for. It leaves the drop out until you confirm no running build or rollback target needs the old column.
3. **Checks additive changes against old readers.** A new column can break old code that reads `SELECT *` rows by position, inserts without a column list, or caches column lists. When such readers exist, the agent puts the new data where they do not look, or ships explicit column lists first.
4. **Keeps locks and backfills short.** Migrations get a short lock timeout so they fail instead of stalling traffic. Indexes on large tables use the non-blocking form outside a transaction. Backfills run in bounded batches, recheck their condition in the write so a value a user just set is kept, and can be safely rerun.
5. **Leaves applied migrations alone.** The agent never edits, renames, or deletes a migration that already ran in a shared environment. It changes course with a new one.
6. **Proves both builds work.** Before reporting done, the agent builds a database from the migrations that already ran, applies the new ones, and runs both the previous build (from git) and the new build against it, checking that each sees the other's writes. If the previous build fails, it cuts the change back to a step that passes.

## What stays up to you

- Confirming that a column or table can be dropped, or that existing data can be rewritten in place.
- Running anything against a production database.

## Example prompts

```text
Rename the `fullname` column on `users` to `display_name` and update the code to match.
```

```text
Record where each user signed up: add a `signup_source` column and accept it in create_user.
```

```text
Add an index on events (account_id, kind) so filtering an account's activity by kind stops scanning.
```
