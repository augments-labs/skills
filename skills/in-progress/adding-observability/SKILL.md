---
name: adding-observability
description: "Adds metrics, alerts, traces, or logs that people will rely on to notice production failures. Load it before the first edit when asked to instrument code, track latency or errors, add monitoring to a job, or write or finish an alert. Skip it for reading or explaining existing metrics and for bug fixes that do not touch instrumentation."
---

# Adding observability

A signal is only useful if it is there, and right, on the worst day. Most
instrumentation bugs are silent: the metric exists, the dashboard renders,
and the alert never fires. Build every signal for the failure it must show.

## 1. Measure what users feel

- Instrument the user-visible result of the operation: did it succeed, and
  how long did it take. Prefer that over liveness, CPU, or internal step
  counts.
- Find the house helpers first (a metrics module, a push client for jobs,
  the alert file and its query language) and use them. Do not add a second
  library.

## 2. Record every exit

- Take the start time before any work, and record duration and outcome in a
  `finally` (or the language's equivalent), so errors, timeouts, and
  cancellations are counted too. A metric that only records on the success
  path reports a perfect service during an outage.
- Give each failure kind a distinct outcome value (`ok`, `error`,
  `timeout`, `rejected`) when the code can tell them apart. Re-raise; never
  swallow an exception to record it.

## 3. Keep labels bounded

- Label values come from a short, fixed list you can write down: route
  templates, outcome, reason, method. Never user ids, emails, order ids,
  request ids, raw paths, query text, or amounts. Each new value creates a
  new series forever.
- Put per-request detail in logs or traces, not labels.

## 4. Create every series at startup

- A labelled counter has no series until its first increment. `rate()` and
  `increase()` need a prior sample, so the first failure after a deploy is
  invisible and an alert on it never fires.
- At module load, call `.labels(...)` once for every known value of a
  failure or reason label, so each series exists at zero.

## 5. Match buckets to the alert

- Read the alert threshold (or SLO) before choosing histogram buckets, and
  put a bucket edge exactly on it, in the metric's unit. Between edges,
  `histogram_quantile` interpolates, so a 300 ms alert on buckets of 250 ms
  and 500 ms fires on a guess.
- Alert on quantiles from histogram buckets, never on averages or on
  pre-computed per-instance summaries, which cannot be aggregated.

## 6. Jobs and CLIs must push, and push on failure

- A process that exits before a scrape is never seen by a pull-based
  scraper. Use the push or flush path the codebase provides.
- Flush in a `finally` or exit handler so a crashed run still reports, and
  record a success flag and a last-success timestamp. Alert on the
  timestamp being too old, which also catches the job not running at all.
- Keep the exit code: a job that fails must still exit non-zero.

## 7. Carry context across hops

- When work crosses a thread, queue, task, or service boundary, pass the
  trace or request context with it, or the trace ends at the boundary.
- If traces are head-sampled, make sure errors are still kept (sample on
  error, or log the trace id with the error).

## 8. Alerts someone can act on

- Alert on the symptom users feel (error ratio, latency quantile, job
  staleness), with a `for` window long enough to skip a single blip.
- Every rule names an owner and a summary that says what is wrong and the
  first thing to check.

## 9. Prove each signal

- Write a test that drives the failure path and asserts the metric moved:
  a failed call increments the failure series and still observes duration;
  each reason series exists at zero right after startup; a failed job run
  still flushes.
- Run the test suite before you finish, and say which signals you added and
  which alert reads each one.
