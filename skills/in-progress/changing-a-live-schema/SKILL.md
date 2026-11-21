---
name: changing-a-live-schema
description: "Changes a database schema that live traffic uses so every build running during the rollout keeps working. Load it before your first edit when a task adds, renames, retypes, or removes a column, table, index, or constraint, writes a backfill or data migration, or adds a migration file for a database that serves production, even when the change looks like one ALTER statement. Skip it for a database nothing serves yet (a new project, a test-only database) and for questions that change nothing."
---

# Changing a live schema

A migration runs once, while the build now in production is still serving.
Until the rollout ends, and after any rollback, the database must work for
that build and for the one you are writing. A change that is correct for the
new code alone is not done.

## Before you edit

1. Read how deploys run: when migrations apply relative to the rollout,
   whether old and new builds serve side by side, and whether a rollback
   undoes migrations.
2. Read the migration runner: whether it wraps each file in a transaction,
   whether it sets a lock timeout, and how a file opts out of the
   transaction.
3. Find every reader and writer of what you change in the build now in
   production: queries, models, `SELECT *`, rows unpacked by position,
   `INSERT` without a column list, cached column lists, other services.
4. Note the table's size and write rate. A lock that is harmless on a small
   table stops traffic on a busy one.

## Expand, then contract, across deploys

Never remove or rename something a running build uses in the same deploy
that stops using it. Each step below is its own deploy:

1. **Expand.** Add the new shape beside the old one: a nullable column, a new
   table, an index. The build in production must work unchanged against it.
2. **Write both.** The new build writes both shapes. The old shape stays the
   source of truth for reads, because the old build keeps writing only the
   old shape during the rollout. Reading the new shape now, or "new, else
   old", shows stale values for rows the old build changes.
3. **Backfill** existing rows (see Backfills).
4. **Switch reads** to the new shape once the backfill is done and no running
   build writes only the old shape.
5. **Stop writing** the old shape once no running build reads it.
6. **Contract.** Drop the old shape only after the last build that uses it is
   gone, including rollback targets. Leave the drop out of this change unless
   the owner confirms that; report it as the next step.

A rename is all six steps. Do the step the current state allows without
waiting for confirmation; only the drop waits for the owner. When the task
asks for the whole change at once, leave only that step in the working tree,
keep the tests green, and report the remaining deploys and what each waits
for. A later step left in the tree ships with this deploy.

## Additive changes still break readers

- A new column breaks `SELECT *` readers that unpack rows by position,
  `INSERT` without a column list, and cached column lists in the build now in
  production. If those exist, put the new data where they do not look (a new
  table), or ship explicit column lists first and add the column in a later
  deploy.
- Add a NOT NULL column as nullable or with a default, backfill it, and add
  the constraint after every writer sets it. Add foreign keys and checks
  unvalidated first, then validate in a separate step, where the database
  supports it.

## Locks

- Every DDL statement queues for its table lock. Behind a long transaction it
  waits, and every query on that table queues behind it. Give each migration
  a short lock timeout (a few seconds) in the same session or transaction as
  the statement, so it fails instead of stalling traffic, and make it safe to
  retry. If the runner does not set one, set it in the migration.
- Build an index on a large or busy table with the non-blocking form
  (`CREATE INDEX CONCURRENTLY` or the database's equivalent). It cannot run
  inside a transaction: use the runner's opt-out, one such statement per
  file. A failed build can leave an invalid index behind; drop it before you
  retry, because `IF NOT EXISTS` keeps the invalid one.
- Earlier migrations that skipped these rules are not precedent.

## Backfills

A backfill runs while users write to the same rows.

- Work in bounded batches by key, each in its own short transaction. One
  statement over the whole table holds its locks for the whole run.
- Recheck the condition in the write itself (`WHERE new_col IS NULL`), so a
  value a user set after you read the row is kept. Never read rows in one
  statement and write computed values back by id without that recheck.
- Make it idempotent and resumable: a second run changes nothing, and a
  restart continues where it stopped.
- Change only the target column.

## Applied migrations are history

Never edit, rename, reorder, or delete a migration that ran in any shared
environment. Change course with a new migration.

## Prove both builds work

Before you report done, run a check that:

1. Builds a database from the migrations that already ran, with rows in it.
2. Applies your new migrations.
3. Runs the build now in production (the code before your change, from git)
   against it: its reads and writes on the changed table.
4. Runs the new build against the same database, and checks that each build
   sees the other's writes.

The project's own tests run only the new build, so they cannot show this.
If the build now in production fails the check, the change is not done: cut
it back to a step that passes and rerun. Telling the user to split it does
not make it safe.

## Human-authority stops

- Dropping a column or table, or rewriting existing data in place: ask the
  owner to confirm no running build or rollback target needs it.
- Running anything against a production database.

## Report

State which step of the sequence this change is, what the next deploys must
do, and what each one waits for.
