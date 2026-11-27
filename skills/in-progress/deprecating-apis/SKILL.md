---
name: deprecating-apis
description: "Deprecates, sunsets, or removes a function, endpoint, field, option, or other interface that other code, teams, or partners call. Load it before the first edit for any such task, even when usage looks like zero. Skip it for adding new interfaces or renaming private code."
---

# Deprecating APIs

A deprecation works when every caller finds out in time, in the place they
already look, and keeps working until the owner removes the old interface. A
removal is safe only when you know who still calls it, including the callers
no grep or dashboard shows.

## Before the first edit

- **Find every caller, not just the ones the name shows.** Search for the
  name, then for how code can reach it without spelling it out: names built
  from strings or config (`getattr`, registries, routing tables, job
  configs), reflection and dependency injection, scheduled and monthly jobs,
  queue consumers, scripts, exports, dashboards and queries that read what it
  emits, and generated clients. Read the config the jobs load.
- **Check what the usage data covers.** A counter of zero proves nothing
  about a path it never counted. Note where the counter sits (an HTTP
  handler, one client) and which callers bypass it, and how long it has
  covered: a monthly or quarterly caller needs a full cycle of data.
- **Confirm the replacement exists and matches.** Callers must be able to
  move before you mark the old interface. If the replacement differs (units,
  shape, defaults), say how to convert.
- **Find the conventions the repo already uses** for deprecations: an
  existing counter, header, warning helper, or schema field. Reuse them.

## Marking something deprecated

The old interface must keep behaving exactly as before. Add the signal its
callers' tools understand, once:

- **Library functions:** raise the language's deprecation warning (in Python,
  `warnings.warn(..., DeprecationWarning, stacklevel=2)`) so it points at the
  caller's line, and name the replacement. Do not log a warning on every
  call: a hot path floods logs. Log at most once per process.
- **HTTP endpoints:** on every response of the old endpoint, add
  `Deprecation` (`@<unix seconds>` of when it was deprecated), `Sunset` (an
  HTTP date such as `Mon, 01 Mar 2027 00:00:00 GMT`) when a shutdown date is
  set, and `Link: <replacement>; rel="successor-version"`. Leave the body
  unchanged and the replacement unmarked.
- **Fields and options:** keep the old field with the same value, add the
  new one computed from the source data rather than from the old field (no
  float round trips), and mark the old one deprecated where clients read the
  contract: `"deprecated": true` in JSON Schema or OpenAPI, the schema
  language's own deprecation marker elsewhere.
- **Count every call, per caller.** Add a counter on the deprecated path
  labelled by caller (client id, module, team) so the owner can see who still
  depends on it. Count every call; only the warning is once.

Update tests that pin the old behavior only if they break, and add tests
that the old path still works and emits the signal.

## Removing something

1. Re-check every caller from the search above, not only the usage counter.
2. If any caller remains, migrate it to the replacement with identical
   output (same units, rounding, and format), and test that output, or stop
   and report the caller instead of removing.
3. Remove the code, its route, its tests, and its config entries together,
   and keep the suite green.
4. Keep removal out of a change that marks something deprecated. Removal is
   its own change, after the announced date and the owner's approval.

## What stays with the owner

The shutdown date, any brownout (planned short outages that surface hidden
callers), and the final removal are the owner's decisions. Do not schedule
or run a brownout yourself. When you report, list:

- every caller you found and how you found it, including those the usage
  data misses;
- the signals you added and where callers will see them;
- what still blocks removal.
