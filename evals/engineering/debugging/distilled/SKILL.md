---
name: debugging
description: "Finds the cause of a bug before fixing it. Use when a bug, test failure, flaky or CI-only failure, or unexpected behavior has an unknown cause, or the user asks why something breaks. Skip one-line errors with a visible cause, live outages (contain first), and post-incident reviews."
---

# Debugging

- Reproduce the bug with a rerunnable check before changing code; never patch a cause you have not shown.
- If real users are failing now, contain the impact first.
- Three green local runs do not reproduce a CI or intermittent failure; recreate what differs (parallelism, order, repetition, environment).
- Check test doubles against the real dependency, and treat a nonzero exit beside "all passed" as a runner, cleanup, or teardown failure.
- Confirm the cause against the user's actual records and rerun them end to end.
- Before closing, fix or report every sibling copy, parallel implementation, and other reader of anything your fix changes.
- Revert fixes that miss. After three misses, question the layer and design.
- Ask before probing production or keeping sensitive data.
