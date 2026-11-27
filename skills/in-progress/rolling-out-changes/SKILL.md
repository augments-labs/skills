---
name: rolling-out-changes
description: "Puts a behavior change behind a runtime feature flag or kill switch. Load it before your first edit when a task asks for a flag, a kill switch, a gradual or percentage rollout, a way to turn something off without a deploy, or retiring a flag. Skip it for changing an existing flag's value."
---

# Rolling out changes

A flag is only useful if flipping it, either way, in a running process, does
exactly what the owner expects on every path. A change that works with the
flag on in one handler, but leaks through a job, a cache, or a duplicate code
path, is not done.

## Before the first edit

Find out, from the code and its docs:

- **The flag facility the repo already has.** Use it, and read how it works:
  what an unset flag returns, how percentages pick subjects, and how ops
  change a value in production. Never add an environment variable, config
  key, or new flag store for a runtime switch.
- **Every path that reaches the behavior.** Search for the function you are
  changing, then for the logic it repeats: request handlers, background jobs,
  queue consumers, retries, scheduled digests, admin tools, and fast paths
  that recompute the same value inline. Each one is a path the flag must
  cover.
- **What each path writes that another reads.** Caches, queued messages,
  stored rows, and files written with the flag on can be read later with the
  flag off, and the other way round.
- **How the rollout is watched.** Which metrics or dashboards the team reads
  during a rollout.

## Writing the switch

1. **Unset keeps today's behavior.** The flag store in production does not
   know your flag yet, so an unset flag must behave exactly like the code
   before your change. For a kill switch, unset means keep doing the work,
   so name it for what setting it does (`<feature>_disabled`). Do not rely on a local default file that production does
   not read.
2. **Read it at call time.** Check the flag inside the request, job, or
   function call, never at import, startup, or into a module constant, so a
   flip reaches running processes on their next call.
3. **Decide once, cover every path.** Put the decision in one function every
   path calls, or guard each path you found. A duplicate inline calculation
   that skips the flag means customers see one result and get another.
4. **Pass the same stable subject everywhere.** For a percentage, pass the
   same id (customer, account) on every path, threading it through function
   signatures when needed, so one customer lands in one group across quote,
   charge, job, and email. A flag read without its subject silently stays off
   below 100%.
5. **Check before side effects.** Read the switch before the vendor call,
   email, write, or enqueue it controls, not after.
6. **Make leftovers safe both ways.** Anything one side stores, the other
   side must handle: key caches by the flag's value (or cache inputs both
   sides share and shape the response after the read), and never store a new
   shape the old code reads. A flip must never serve a response cached under
   the other setting.
7. **Tag the signals the rollout is judged by.** Add the group (on or off,
   or the variant name) as a label on the existing success and failure
   metrics, on both sides, so the dashboard can compare groups. Keep the
   metric names the dashboard already graphs.

## Tests

Add tests that use the real flag facility the way ops would:

- **Off:** with the flag unset, every path you found behaves as before.
- **On:** with the flag fully on, every path takes the new behavior.
- **Percentage:** at a partial percentage, one subject gets the same result
  on every path, and the group is visible in the metrics.
- **Flip in one process:** turn it on, use the paths, turn it off, use them
  again, and the other way round. Nothing cached or stored by one side breaks
  or leaks into the other.

Update existing tests whose expectations your labels or new arguments change,
and keep the suite green.

## What stays with the owner

Never turn the flag on in a shared or production environment yourself, and
leave it off in any defaults that ship. When you report:

- the flag name and what unset, on, and a percentage do;
- how to turn it on and what to watch, by metric and label;
- the follow-up to remove the flag once the rollout ends.

## Removing a flag

When asked to retire a flag that is fully on, remove the code that reads it
in one change, and only then the flag from the store, so no build still
running reads a flag that disappeared and falls back to off.
