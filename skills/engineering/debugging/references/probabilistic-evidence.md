# Intermittent, environment-specific, and production failures

Use this when you cannot yet reproduce the failure on demand.

## Write the experiment down before the first run

- **Failure signal:** the exact error, event, or broken invariant.
- **Where:** the environment, version, workers, and data it ran on.
- **Baseline:** how many runs or how long a window, and how many failures, as
  raw counts (3 failures in 40 runs, not "7%").
- **Control:** an unchanged run, commit, or environment to compare against.
- **Decision rule:** what result counts as reproduced, fixed, or
  inconclusive, decided before you look.
- **Stop conditions:** cost, time, privacy, or impact limits.

Use enough runs to tell the effect apart from normal variation. A failure
that shows up in 1 of 5 CI runs needs dozens of clean runs before "fixed"
means anything.

## Reproduce what differs

List every difference between the failing run and your local runs, then
recreate them one at a time or together:

- concurrency: parallel test workers, thread or process pools, more load;
- order: shuffled or reversed test order, a single test run alone;
- repetition: the same test in a loop hundreds of times;
- timing: a slower machine, CPU limits, injected delays, a fake clock;
- environment: environment variables, locale, timezone, dependency versions,
  file system, and network.

Stress the suspect code directly when the test is too slow to repeat. A
race that appears 1 in 5 runs at 4 threads often appears every run at 16.

## Production probes

Before any probe against production, get the user's direct approval for:

- the exact environment, query or probe, time window, and population;
- read-only versus write access, using the least access that works;
- the fields collected, and redaction before anything is stored;
- sampling rate, cost and latency budget, and maximum duration;
- how to stop it, and where the output is kept and for how long.

Prefer existing telemetry and read-only queries. Never log secrets,
credentials, or full payloads because the issue is urgent.

## Keep a replay

Keep the smallest sanitized artifact that reproduces the failure: the input,
the ordering or timing, the seed, the configuration, and the source revision.
If you redact it, show the redacted copy still reproduces the failure.

## Compare fairly

Compare the baseline, the control, and the fix under the same conditions and
the same number of runs. Count hypothesis tests and fix attempts separately.
Zero failures supports only the sample you ran; report it as "0 failures in
N runs", never as proof the bug is gone.
