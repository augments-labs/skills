# LAMPLIGHT

_Owner: catalog team. Last edited by whoever touched it last, sorry._

LAMPLIGHT is our name for the full catalog reindex. The name comes from the
March outage two years ago when the old index went dark and somebody said we
were "lighting the lamps back up one shard at a time". It stuck.

## Background (skip if you know this)

Search does not read the product database. It reads the `catalog-live` alias,
which points at one physical index (`catalog-v<N>`). Writers (the admin UI,
the supplier feed importer, the price service) update the database and push
change events; the incremental indexer (`catalog/indexer.py`) consumes those
events and patches the live index. Most of the time that is enough.

It is not enough when events get dropped. The incremental indexer has no
replay, so anything it missed stays wrong in search until LAMPLIGHT rebuilds
the index from the database. Over the years that has looked like:

- products we deleted (or unpublished) still showing up in search results,
  sometimes for weeks;
- a supplier bulk import finishes and the new products never appear in search
  (the importer floods the event queue and the indexer drops the overflow);
- search showing old prices while the product page shows the new price,
  usually after a sale goes live, because the price service batch-publishes;
- whole categories looking stale after a category merge or rename;
- the `catalog_search_drift_high` alert (sampled drift between the database
  and the index above 2% for 15 minutes). That alert is basically "run
  LAMPLIGHT";
- any change to the index mapping in `catalog/indexer.py` (new field,
  changed analyzer): mappings only apply to a freshly built index.

LAMPLIGHT does NOT help with slow search. If p95 latency is up, that is the
query cache or a hot shard; see `docs/runbooks/search-latency.md`. Running a
reindex during a latency incident makes it worse (the build eats cluster
CPU). Also not for typos or synonyms ("tshirt" vs "t-shirt"), that's the
synonyms file, no reindex needed... actually you do need to reopen the index,
but not LAMPLIGHT. Ask in #catalog.

## Before you start

Check the freeze calendar (no LAMPLIGHT during a sale launch window, the
price service is batch-publishing then and you'll fight it). Tell #catalog
you're starting.

You need `catalogctl` (in `scripts/`, run it with `python3 scripts/catalogctl`)
and the `catalog-admin` role.

## The procedure

From Slack, mostly what Dana does:

> ok so: pause writes, build the shadow, warm it, compare counts, swap,
> resume. don't forget to resume. last time someone forgot and the admin UI
> was read-only for an hour and a half

1. Dry run first: `make lamplight-dry`. It prints the plan and the current
   alias target. If the alias already points at a `-shadow` index, someone
   else's LAMPLIGHT is half done. Stop and ask in #catalog; do not start a
   second one.
2. Pause writers: `python3 scripts/catalogctl writes pause`. This makes the
   admin UI read-only and holds the supplier importer. Writes must be resumed
   within 20 minutes, no matter what state the rebuild is in: the supplier
   feed's own timeout is 30 minutes and after that it drops the whole batch.
   If the build won't finish in time, resume writes and try again off-peak.
3. Build: `python3 scripts/catalogctl index build --shadow`. Takes 6 to 12
   minutes for ~1.4M products.
4. Warm: `python3 scripts/catalogctl index warm --shadow --min-hit 0.95`.
   Don't swap a cold index; the first minutes after swap will time out for
   customers.
5. Compare counts: `python3 scripts/catalogctl index count --shadow` vs
   `python3 scripts/catalogctl db count --published`. The shadow must be
   within 0.5% of the database. If it's off by more, do NOT swap: something
   is wrong with the build (usually the mapping). Resume writes and
   investigate.
6. Swap: `python3 scripts/catalogctl alias swap --to shadow`.
7. Resume writers: `python3 scripts/catalogctl writes resume`.
8. Keep the old index for 24 hours (that's your rollback:
   `catalogctl alias swap --to previous`). Never delete the index the alias
   currently points at; `catalogctl index gc --keep 2` after 24h is the only
   cleanup.

## Afterwards

Post the drift number from `catalogctl drift sample` in #catalog. It should
be under 0.2%. If the drift alert fired, ack it after the swap, not before.

## FAQ

Q: Can I run just one category? A: No. Partial rebuilds were removed in v3.

Q: Can I skip warming at night? A: Traffic is lower but not zero. Warm it.

Q: Who approves? A: Nobody, just tell #catalog. During the freeze window, the
on-call lead.
