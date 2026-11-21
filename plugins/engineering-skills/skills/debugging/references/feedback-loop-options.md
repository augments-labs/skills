# Feedback loops

A feedback loop is a command you can rerun that tells you whether the bug is
present. Prefer a deterministic loop. When the failure is intermittent or only
happens in production, a loop that counts failures over a declared sample is
valid, as long as you set the sample size and the pass threshold before you
look at results.

## Ranked, tightest first

1. **A failing unit test:** the bug written as an assertion.
2. **A request script:** call the endpoint and assert the status and body.
3. **A CLI run against a saved input:** feed the input and diff the output
   against a known-good snapshot.
4. **A headless UI script:** drive the interface and assert on the result.
5. **A replayed trace:** capture a real failing request or session and replay
   it.
6. **A throwaway harness:** a short script that calls only the suspect unit
   with the triggering input.
7. **A property or fuzz loop:** generate inputs until the bug appears; then
   keep that input as a case.
8. **A bisection script:** script the good-versus-bad check, then bisect
   commits or inputs to the boundary.
9. **A differential loop:** run the old and new versions on the same input;
   the difference is the bug.
10. **A bounded log or metrics query:** count one exact failure signature over
    a fixed window and population, next to a baseline.
11. **A sampled production probe:** only with the user's direct approval,
    redaction, rate and duration limits, and a way to stop it.
12. **A script the user runs:** give exact commands, and ask for the raw
    output and the environment details back.

## Check the loop before you trust it

- It fails on the known broken state and passes on a known good one (an older
  commit, a working input, another environment).
- Before a passing run rules out a cause, show that the loop ran your edited
  code. A stale build, a cache, an installed package shadowing the source,
  another worktree, or a container that was not rebuilt all return the old
  behavior. A marker your edit prints is enough.
- For a loop that counts failures, keep the exact failing cases and report
  counts with their denominator.

## When no loop is possible

That is the finding. Say so, list what you tried, and ask for what you need:
access to the environment, a captured failing input, or permission to add
bounded instrumentation. Do not patch without a loop.
