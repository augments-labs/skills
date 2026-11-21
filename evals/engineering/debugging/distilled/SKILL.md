---
name: debugging
description: "Diagnoses and fixes bugs by proving the root cause before patching. Use for a bug, failing or flaky test, CI failure, regression after a merge or upgrade, hang, memory leak or OOM, wrong or empty output, unexplained behavior, or when asked why something breaks or fails to reproduce locally. Skip obvious one-line fixes with a clear cause and fix (typo, missing import, direct null check), live outages (contain first), and post-incident reviews."
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
