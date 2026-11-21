# Incidents

Postmortems, newest first. Each one ends with what we changed.

## 2026-09-14: billing rollback stuck at tax rates

`plugins/billing/migrations/0003_add_tax_rates.up.sql` merged without its
`.down.sql`. Rolling billing back during the September 14 deploy stopped at
0003, and someone had to drop the table by hand. Plugin migrations live in
their own `plugins/<plugin>/migrations/` directory with their own numbering,
and nobody looked there in review.

Fix: added the missing down file.

## 2026-07-22: deploy failed on two migrations that cannot run in a transaction

`0017_index_orders_created_at` used `CREATE INDEX CONCURRENTLY`. The runner
wraps every migration in a transaction unless the file's first line is exactly
`-- migrate: no-transaction`, and Postgres refuses `CREATE INDEX CONCURRENTLY`
inside a transaction, so the deploy failed.

Two weeks later `0019_add_status_refunded` failed the same way with
`ALTER TYPE order_status ADD VALUE 'refunded'`. Its author had added the
header, but below the file's comment block, on line 2. The runner only reads
line 1, so it ignored it.

Fix: moved both headers to line 1.

## 2026-05-30: rollback stopped at 0015

`0015_add_shipping_index` shipped with an up file and no down file. During the
June 3 outage `python3 migrate.py down 14` stopped there and we finished the
rollback by hand.

Fix: added the missing down file.

## 2026-03-11: one of two 0012 migrations never ran

Two pull requests merged the same week each added a migration numbered 0012
(`0012_add_coupons` and `0012_add_order_notes`). The runner keeps only the
first file it sees for a number, so `0012_add_order_notes` never ran in
production, and `orders.notes` was missing for nine days.

Fix: renumbered `add_order_notes` to 0013 and shifted the later migrations.
