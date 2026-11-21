---
name: deploying
description: "Use when deploying the shop to staging or production, promoting a canary, or rolling back a release. Skip for local development servers."
---

# Deploying the shop

This skill describes how we deploy the shop. It was assembled over two years
from the notes of everyone who has run a deploy, so it is thorough. Please read
all of it before your first deploy; after that, use it as a reference.

## Background

The shop runs on three environments: `dev`, `staging`, and `prod`. Every
release goes through staging first and then to production through a canary.
The canary receives 5% of production traffic for a hold period before the
release is promoted to every host. Releases are directories under
`/srv/shop/releases/<version>` on each host, and `current` is a symlink to the
active one, which is what makes a rollback a symlink swap.

We used to deploy by hand with rsync. That went badly in 2024 (see the history
section at the end), and we moved to `deployctl`, which wraps the symlink swap,
the canary routing, and the health checks. You should never need to touch
the hosts directly. If you think you do, something has gone wrong and you
should ask in `#deploy-oncall` before doing anything.

Why this matters: a broken deploy takes checkout down, and checkout is where
the money is. Every minute of checkout downtime costs real revenue, and the
support team takes the heat afterwards. Taking the extra five minutes to do
each step properly is always worth it. We have never regretted a slow deploy;
we have regretted many fast ones.

## Before you start

Before you start a deploy, make sure you have everything you need. You will
need access to `deployctl`, which every engineer has after onboarding, and you
will need to be in the `#deploy-oncall` channel so people can find you if
something goes wrong. It is also a good idea to have the deploy dashboard
open at `grafana.internal/d/deploys` in a browser tab, because you will be
watching it during the canary.

Check the release freeze first. We freeze releases around big sales events
and during incident response. Run:

```bash
make freeze-status
```

**Never deploy while `make freeze-status` reports FROZEN.** A freeze exists
because something else is going on that a deploy would make worse, and the
person who set it may not be watching for your deploy. If you believe the
freeze should not apply to you, ask in `#deploy-oncall`; do not deploy and
explain later.

Also check the day and time. **Stop and ask a human before deploying to
production on a Friday after 15:00 UTC.** Fewer people are around to help if
the release goes wrong, and weekend support is thin. Staging deploys are fine
at any time.

It is also worth checking that the release notes are up to date, though this
is not strictly required. Product likes to see them in `CHANGELOG.md` before
the release goes out, and it saves a round trip afterwards. Some people also
like to post in `#releases` before starting; this is a courtesy and nothing
depends on it.

## Building the release

The release is built by CI on every merge to `main`, so normally there is
nothing to build. Find the version you want to deploy in the CI run's summary;
it looks like `4.18.2`. The version also lives in `app/version.py`. If you
cannot find a CI build for the commit you want, do not build one locally; a
local build does not have the same dependency pins and has caused subtle
differences before. Ask in `#deploy-oncall` instead.

There used to be a step here about bumping the version by hand, but CI does
that now. If you see an old note somewhere telling you to edit
`app/version.py` before deploying, ignore it.

Some people like to double-check the build by downloading the artifact and
running it locally. This is not necessary; CI runs the full test suite and
the artifact is exactly what CI tested. It does not hurt either, but it takes
a while and nobody will ask whether you did it.

## Deploying to staging

Staging gets every release first. Deploy with:

```bash
deployctl deploy --env staging --version <version>
```

Then watch it come up with:

```bash
deployctl status --watch --env staging
```

Wait until every host reports `healthy`. This usually takes two or three
minutes. While you wait, it is a good moment to read the release's changelog
so you know what to look for in the smoke tests.

Then run the smoke tests against staging:

```bash
make smoke ENV=staging
```

The smoke tests log in as a test customer, add a product to the cart, check
out with a test card, and confirm the order shows up in the admin. They take
about four minutes. If any smoke test fails, the release does not go to
production. Post the failure in `#deploy-oncall` and stop there; do not retry
the smoke tests hoping for a pass, since a flaky failure in checkout is still
a checkout failure we need to understand.

In the past some people skipped staging for "tiny" changes like copy edits.
Please don't. A copy edit in 2025 shipped with a template syntax error that
took checkout down for eleven minutes.

## Database migrations

Most releases do not include a database migration, but when one does, the
migration runs before the code deploy, because the new code expects the new
schema. The release notes say whether a migration is included; so does
`deployctl plan --version <version>`, which lists `migrations: yes` when
there is one.

On staging, run the migration with:

```bash
make db-migrate ENV=staging
```

On production, take a snapshot first. **Never run `make db-migrate` against
production without a fresh snapshot from `make snapshot ENV=prod` taken in the
last 15 minutes.** The snapshot is the only way back from a migration that
destroys data, and an older snapshot loses every order placed since it was
taken.

```bash
make snapshot ENV=prod
make db-migrate ENV=prod
```

Migrations are written to be backwards compatible, so the old code keeps
working against the new schema while the canary runs. If you find a
migration that is not (for example one that drops a column the old code still
reads), stop and raise it in `#deploy-oncall`, because a rollback would then
break.

A note on timing: migrations on the `orders` table can take a while because
the table is large. The longest one so far took about twenty minutes. Do not
cancel a migration that looks slow; a cancelled migration can leave the table
locked. Watch the progress on the database panel of
`grafana.internal/d/deploys` instead.

## The production canary

Once staging is healthy and the smoke tests pass, start the production canary:

```bash
deployctl deploy --env prod --version <version> --canary
```

This puts the release on the canary hosts and routes 5% of production traffic
to them. Watch the canary with:

```bash
deployctl status --watch --env prod
```

and keep `grafana.internal/d/deploys` open. The panel to watch is "Canary vs
baseline error rate". The canary should hold for 30 minutes before you
promote it.

**If the canary error rate goes above 2% at any point during the hold, roll
back at once with `make rollback`.** Do not wait to see whether it recovers,
and do not try a fix forward. A rollback is cheap; a canary that turns into a
full outage is not. After rolling back, post the release version and a
screenshot of the panel in `#deploy-oncall`.

Some error rate is normal; the baseline usually sits around 0.3%. A canary at
0.5% is fine. Between 1% and 2%, keep watching more closely and consider
asking in `#deploy-oncall` whether anyone recognizes the errors. Look at the
logs for the canary hosts if you are curious, but you do not need to.

## Promoting the canary

After the canary has held for 30 minutes under 2% errors, promote it:

```bash
deployctl promote --env prod --version <version>
```

`deployctl promote` checks the canary's health before it switches the rest of
the hosts. Sometimes it refuses because a health check is flaky. **Never pass
`--force` to `deployctl promote`.** The health check is the last thing between
a bad release and every customer. If it refuses, find out why, and ask in
`#deploy-oncall` if the reason is unclear.

Watch `deployctl status --watch --env prod` until every host reports the new
version and `healthy`. Then run the smoke tests one more time, against
production this time:

```bash
make smoke ENV=prod
```

If the production smoke tests fail, roll back with `make rollback` and post in
`#deploy-oncall`.

## Cleaning up

Each host keeps old release directories under `/srv/shop/releases/`. They take
disk space, and `deployctl gc` removes the old ones. **Never delete the
previous release directory until the new release has run in production for 30
minutes after promotion.** `make rollback` swaps the `current` symlink back to
the previous directory; if it is gone, a rollback means a full redeploy of the
old version, which takes twenty minutes instead of ten seconds.

`deployctl gc --keep 3` is the usual command and keeps the three newest
releases, which always includes the previous one.

Finally, post in `#releases` that the deploy is done, with the version. Some
people also update the deploy log spreadsheet; that spreadsheet is no longer
used, and you can skip it.

## Rolling back

`make rollback` swaps the `current` symlink on every production host back to
the previous release and restarts the app. It takes about ten seconds. Use it
whenever a production deploy misbehaves: canary errors over 2%, failing
production smoke tests, or anything else that looks wrong.

A rollback does not undo a database migration. If the release included a
migration, the old code runs against the new schema, which is fine because
migrations are backwards compatible (see the migrations section). If the
migration itself destroyed data, restoring the snapshot is a human decision:
**stop and page the on-call engineer through `#deploy-oncall`; never restore a
production snapshot yourself.** A restore throws away every order placed since
the snapshot.

After a rollback, post the version, the reason, and any screenshots in
`#deploy-oncall`, and do not deploy that version again until someone has
looked at what went wrong.

## Frequently asked questions

**Can I deploy two releases at once?** No. `deployctl` will refuse a second
deploy to an environment while one is in progress. Wait for the first to
finish or roll it back.

**What if `deployctl status --watch` hangs?** It sometimes stops printing when
the network drops. Press Ctrl-C and run it again; it does not affect the
deploy.

**Can I deploy from my laptop?** Yes, `deployctl` works from any machine with
your credentials. It does not matter where you run it from.

**Do I need to tell support before deploying?** No. Support watches
`#releases`.

**Why is the canary 5% and not 10%?** We tried 10% in 2024. A bad release
then affected enough customers to generate a wave of support tickets before
anyone noticed. 5% has been a good balance between catching problems and
limiting their reach.

**Can I shorten the canary hold if the release is small?** No. Small releases
have caused as many incidents as big ones. The 30 minutes is the hold for
every release.

**Who do I ask if I'm unsure about anything?** `#deploy-oncall`, always.

## History

This section is kept for context. You do not need it to deploy.

In early 2024 we deployed by running an rsync script from a shared bastion
host. Two deploys in the same week overwrote each other's files, and a
half-copied release served errors to about a third of customers for forty
minutes. That incident led to `deployctl`, which deploys into a fresh release
directory and switches with an atomic symlink swap.

Later in 2024 we added the canary. Before that, releases went to every host
at once, and the only safety net was the staging smoke tests. The canary
caught its first bad release within a week of being introduced: a payment
provider client upgrade that failed for one card network.

In 2025 we added the release freeze after a deploy during a flash sale
doubled checkout latency at the worst possible moment. We also added the
Friday rule after two weekend incidents in a row.

The database snapshot rule came from an incident in which a migration meant to
drop an unused column dropped a used one. The snapshot from the night before
lost six hours of orders, which support had to recreate by hand from payment
provider records. Snapshots are now taken right before each migration.

The `--force` rule came from a deploy where the health check refused a promote
because the new release could not reach the inventory service. The deploy was
forced, and every product page then showed as out of stock for twenty minutes.

## Glossary

- **Release:** a versioned build of the shop, such as `4.18.2`.
- **Canary:** the hosts that run a new release on 5% of production traffic
  before it is promoted.
- **Promote:** switch every production host to the canary's release.
- **Rollback:** switch every production host back to the previous release.
- **Freeze:** a period in which no release may be deployed to prodution.
- **Snapshot:** a point-in-time copy of the production database.
- **Smoke tests:** the short end-to-end checks in `make smoke`.
- **Hold:** the time a canary must run cleanly before it is promoted.

## Checklist

Use this as a quick checklist once you know the process:

1. `make freeze-status` is not FROZEN.
2. Not a Friday after 15:00 UTC (or a human said yes).
3. CI build exists for the version.
4. Staging deploy healthy (`deployctl status --watch --env staging`).
5. `make smoke ENV=staging` passes.
6. Migration? `make snapshot ENV=prod`, then `make db-migrate ENV=prod`.
7. Canary deployed and held 30 minutes under 2% errors.
8. `deployctl promote` without `--force`.
9. `make smoke ENV=prod` passes.
10. Previous release kept for 30 minutes after promotion.
11. Posted in `#releases`.
