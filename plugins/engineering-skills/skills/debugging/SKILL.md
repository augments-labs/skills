---
name: debugging
description: "Diagnoses and fixes bugs by proving the root cause before patching. Load it before your first command when a task reports something broken and leaves the diagnosis to you, or asks why something misbehaves: a bug, failing or flaky test, CI failure, crash, regression after a merge, upgrade, or new feature, rejected input, hang, leak or OOM, or output with wrong values or counts, or missing or empty, even when the error seems to point straight at the fix. Skip it when the user has already diagnosed it and spelled out the change (what to show for a missing value, a typo, an import to add), for live outages (contain first), and for post-incident reviews."
---

# Debugging

Prove the cause with a runnable signal before you change code. A fix you
cannot trace to a cause you have shown is a guess. The goal is a system that
behaves correctly, not a green suite: a test only witnesses the code it runs.

## When to skip

- The error already shows both the cause and the fix (a typo, a missing
  import, a null check with a known fallback). Fix it directly.
- Real users are failing right now. Contain first (roll back, turn off the
  flag, fail over), or ask the user to, then come back for the cause.
- A review of how an already-fixed bug got past its safeguards.

## Step 1: Reproduce

1. Write down the symptom, the command that shows it, and the expected versus
   observed result.
2. Build the fastest deterministic loop that shows the bug: a failing test, a
   request script, or a throwaway script that calls only the suspect code. If
   no obvious loop exists, load `references/feedback-loop-options.md` before
   you settle on one.
3. Confirm the loop fails on the broken state for the reported reason, not on
   a neighboring problem.
4. When a failure is intermittent, depends on timing or test order, or
   appears in only one environment, load
   `references/probabilistic-evidence.md` before your first experiment.
   Passing three local runs does not reproduce a CI failure.
5. If you cannot build a loop, stop. Say what you tried and ask for what
   would unblock you.

## Step 2: Find the cause

1. If the report, code comments, or history name earlier fix attempts, revert
   all of them first and rerun the loop on that clean state. An attempt that
   did not fix the bug is not evidence. Restore one only if a check whose
   expected value comes from the spec or the real dependency fails without it.
2. Search for the exact error text in the code and the logs.
3. List only the causes the evidence supports and a probe could prove wrong.
   For each, state what you expect to see if it is true, then run the probe.
4. Before you blame product code, check the scaffolding: test doubles (see
   the next section), a nonzero exit next to an "all passed" summary (a hook,
   cleanup, or teardown failed), configuration, environment, dependency
   versions, data, and flag state.
5. Make sure the loop runs the code you edited: a stale build, a cache, an
   installed copy, or an unrebuilt container returns the old behavior.
6. When the user saw the failure in records you can read (logs, an export, a
   failed batch), confirm the cause against those exact records and rerun
   them after the fix. They often hold a second problem the first one hid.

## Test doubles

Any mock, fake, stub, golden file, or recorded response that the failing
code path or its tests use is a suspect until you show it matches the real
thing. Fixing only the member the failing test hit leaves the rest drifted,
and the suite stays green while production breaks.

1. Open the real implementation and the double side by side. For every
   public member of the real one, compare: parameter names, order, which are
   keyword-only, defaults; the return type; what it raises for unknown,
   missing, or duplicate input; how it normalizes input (case, whitespace,
   units); the order of returned collections; side effects. Read the real
   one's docstrings and its own tests, not only its code.
2. Make the double match on every point, including members no failing test
   touches. Callers may pass any argument by name, so a renamed parameter is
   drift.
3. Prove the match with one check that makes the same calls on both and
   compares the results: run the real implementation's tests against the
   double, or add a contract test parameterized over both. Where the real one
   needs a network or disk, replace only that lowest layer. Build a mock from
   the real interface so a call the real one rejects fails.
4. For golden files and snapshots, regenerate from the real code after the
   intended change, then read the diff line by line. Every changed line must
   follow from that change; anything else is a bug to fix, not to record.
5. Change product code to fit a double only after step 3 shows the double is
   right.

## Step 3: Fix and close

1. If the user asked only for a diagnosis, report the cause and the evidence,
   and stop.
2. Fix the layer where the cause lives. A data, permission, or infrastructure
   problem needs that fix, not a code workaround, unless the request asks for
   code that handles that input. Then write that code, keep it to the inputs
   that fail today, and report the upstream cause.
3. Turn the reproduction into a regression test that fails before the fix and
   passes after it.
4. Search for every other site with the same cause: copies of the code,
   sibling implementations (sync and async clients, v1 and v2 handlers),
   other callers, and every other reader of a flag, cache, or shared field
   your fix changes. Search for the pattern, not the exact line. Fix the
   sites the request covers, each with its own failing check, and report the
   rest.
5. If a fix does not make the loop pass for the reason you predicted, revert
   it before you try another. Stacked misses hide which change did what.
6. Remove temporary instrumentation, or report what you left in place.

## Before you report done

Confirm each with output from this session, not memory:

- The loop failed before your fix and passes after it, for the predicted
  reason.
- Every double the failing path uses passed the check in "Test doubles"
  step 3.
- No earlier fix attempt remains unless a check proves it is needed.
- Every other site with the same cause is fixed or reported.
- The project's full test command exits 0, and you read its raw output.

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

- Timing bugs can vanish under logging or a debugger. Compare runs with and
  without the instrumentation before you trust a quiet result.
- Zero failures in a small sample supports only that sample. Report the raw
  counts, such as 0 failures in 200 runs, never "cannot happen".
