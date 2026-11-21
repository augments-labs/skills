---
name: debugging
description: "Diagnoses and fixes bugs by proving the root cause before patching. Use for a bug, failing or flaky test, CI failure, regression after a merge or upgrade, hang, memory leak or OOM, wrong or empty output, unexplained behavior, or when asked why something breaks or fails to reproduce locally. Skip obvious one-line fixes with a clear cause and fix (typo, missing import, direct null check), live outages (contain first), and post-incident reviews."
---

# Debugging

Prove the cause with a runnable signal before you change code. A fix you
cannot trace to a cause you have shown is a guess, and an intermittent
failure is never permission to guess.

## When to use

- A bug, failing or flaky test, CI failure, regression after a merge or
  upgrade, hang, memory leak or OOM, wrong or empty output, or unexplained
  behavior whose root cause is not yet verified.
- **Skip** obvious one-line fixes where the error already shows both the cause
  and the fix, such as a typo, a missing import, or a direct null check with a
  known fallback. Fix those directly.
- **Skip** diagnosis while real users are failing right now. Contain the
  impact first (roll back, turn off the flag, fail over), or ask the user to,
  then come back to find the cause.
- **Skip** reviews of how an already-fixed bug got past its safeguards.

## Step 1: Reproduce

1. Write down the symptom, the command that shows it, and the expected
   versus observed result.
2. Build the fastest deterministic loop that shows the bug: a failing test, a
   request script, a CLI run against a saved input, or a throwaway script
   that calls only the suspect code. If no obvious loop exists, load
   `references/feedback-loop-options.md` before you settle on one.
3. Confirm the loop shows this bug. It must fail on the broken state for the
   reported reason, not on a neighboring problem.
4. A failure seen in CI that passes the three times you run it locally is not
   reproduced. When a failure is intermittent, depends on timing or test
   order, or appears in only one environment, load
   `references/probabilistic-evidence.md` before your first experiment, and
   reproduce it under the conditions that differ: parallel workers, shuffled
   order, repeated runs, load, seeds, clock, and environment variables.
5. If you cannot build a loop that shows the bug, stop. Say what you tried and
   ask for what would unblock you: access, a captured failing input, or
   permission to add instrumentation.

## Step 2: Find the cause

1. Search for the exact error text in the code and the logs first.
2. List only the causes the evidence supports and that a probe could prove
   wrong. For each, state what you expect to see if it is true, then run the
   probe. Rule causes out; do not collect them.
3. Before you blame product code, check the scaffolding around it:
   - A test double (mock, fake, stub, fixture) that drifted from the real
     dependency. Compare its signature, return type, and behavior with the
     current real code.
   - The process exit code. A nonzero exit next to an "all passed" summary
     means the runner, a hook, a cleanup step, or teardown failed.
   - Configuration, environment, dependency versions, data, and flag state.
4. Make sure the loop runs the code you edited. A stale build, a cache, an
   installed copy shadowing the source, or a container that was not rebuilt
   all return the old behavior. Print a marker if you are unsure.
5. A correlation, one quiet run, or "the logs look fine" is not a cause.
6. When the user saw the failure in records you can read (logs, a database
   export, a failed batch file), confirm your cause against those exact
   records, and rerun them end to end after the fix. A reproduction on input
   you built proves the path exists, not that it is the one they hit, and the
   real records often hold a second problem the first error hid.

## Step 3: Fix and close

1. If the user asked only for a diagnosis, report the cause and the evidence,
   and stop.
2. Fix the layer where the cause lives. A data, permission, or infrastructure
   problem needs that fix, not code that works around it; a broken test
   double needs the double fixed, not product code bent to match it.
3. Turn the reproduction into a regression test that fails before the fix and
   passes after it.
4. Before you close, search for every other site with the same cause: copies
   of the code, sibling implementations (sync and async clients, v1 and v2
   handlers, each platform's version), other callers, and every other reader
   of a flag, cache, or shared field your fix changes. Search for the
   pattern, not only the exact line, since copies are rarely identical. Fix
   the sites the request covers, each with its own failing check, and report
   the rest.
5. Rerun the loop on the fixed state, then the project's checks. Read the raw
   output, including the exit code.
6. If a fix does not make the loop pass for the reason you predicted, revert
   it before you try another. Stacked misses hide which change did what. The
   same goes for earlier fixes you find that never worked: remove them.
7. Remove temporary instrumentation, or report what you left in place.

## Circuit breaker

Count applied fixes, not hypotheses you ruled out. After three applied fixes
have missed, stop patching. Question the reproduction, your model of the
cause, the layer (a cache, configuration, a downstream service, the build),
the environment, and the design, once. If a fix on the revised model also
misses, stop and report what you ruled out, the evidence, and what you need
next.

## Human-authority stops

- Running any probe, query, or instrumentation against production. Ask first,
  naming the exact environment, query, time window, and data collected.
- Keeping logs, dumps, or records that hold personal data, credentials, or
  secrets beyond the session. Ask first, and redact before you store
  anything.

## Gotchas

- Timing bugs can vanish when you add logging or a debugger. Compare runs
  with and without the instrumentation before you trust a quiet result.
- Zero failures in a small sample supports only that sample. Report the raw
  counts, such as 0 failures in 200 runs, never "cannot happen".
