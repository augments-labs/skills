# Skills we tested and left out

Every skill in `engineering-skills` has to beat a no-skill baseline on the same tasks before it ships. When a draft does not, it is dropped, even when its advice is sound. This page records the drafts that were dropped, what each one tried to fix, and what the measurements showed, so you can see why the pack does not include them.

The runs used the same setup as the [skill catalogue](skills.md): each task ran with the draft loaded (`skill`) and without it (`none`), with hooks turned off, on small, medium, and large models. A trap is a task with a hidden hazard and a script that checks whether the agent avoided it.

## How to read these results

A draft is dropped when the baseline already avoids the hazards it targets. In that case the skill only adds context, tool calls, and time to your sessions. If a newer model starts failing these traps, the draft can come back with fresh evals.

## `deprecating-apis`

- **What it tried to fix:** Deprecating or removing a function, endpoint, field, or option that other code, teams, or partners call. It covered finding callers that no grep or usage counter shows (names built from config, scheduled jobs), checking what the usage data actually covers, keeping the old interface working, adding the signal each kind of caller understands, counting every call per caller, and migrating remaining callers with identical output before removal.
- **Traps:** A small billing service with v1 and v2 invoice endpoints, a client library, a usage counter with monthly exports, a JSON Schema, and config-driven jobs. The four traps were removing an endpoint whose function a monthly job still reaches through a name built from config; deprecating a library function with a warning that points at the caller's line, at most one warning log per process, and every call counted; deprecating an endpoint with standard `Deprecation`, `Sunset`, and `Link` headers and calls counted per client; and deprecating a dollars field for an exact integer cents field plus a `deprecated` flag in the schema.
- **Results (2 runs per trap):** large 8/8 with the skill and 8/8 without, medium 8/8 and 8/8, small 8/8 and 8/8.
- **Cost:** The skill used about 1.3 to 1.5 times as many tool calls.
- **Why it was dropped:** The baseline avoided every hazard on every model.
- **Limits of the test:** The prompts said who depends on each interface (partners, other teams, mobile clients), and the fixture is small enough that one search finds the config-driven caller. A retest should drop those hints and use a larger codebase.
- **Tested files:** The draft and its eval cases are in commit `de4a3ca`, under `skills/in-progress/deprecating-apis/` and `evals/engineering/deprecating-apis/`.

## `rolling-out-changes`

- **What it tried to fix:** Putting a change behind a runtime feature flag or kill switch so that flipping it, either way, in a running process does what you expect on every path. It covered using the repo's existing flag facility, keeping today's behavior when the flag is unset, reading the flag at call time, guarding every path (handlers, jobs, caches, duplicated logic), passing the same customer to percentage checks everywhere, labelling the rollout's metrics by group, and leaving the switch for you to turn on.
- **Traps:** A small shop service with a runtime flag store, checkout metrics, a quote cache, background jobs, and a recommendations vendor. The four traps were free shipping that must apply to quotes, checkout, and saved-cart repricing alike; a kill switch that must stop every vendor call, including the weekly digest, without a restart; a stricter address check whose checkout metrics must tell the two groups apart; and a quote breakdown whose cache must stay correct when the flag flips.
- **Results (2 runs per trap):** large 8/8 with the skill and 8/8 without, medium 8/8 and 8/8, small 8/8 and 6/8. The only gap was the small model leaving checkout metrics unlabelled, in both runs.
- **Cost:** The skill used about 1.2 to 2 times as many tool calls.
- **Why it was dropped:** One trap on one model is too narrow a gain to justify loading the skill for every flag request.
- **Tested files:** The draft and its eval cases are in commit `55bd6f7`, under `skills/in-progress/rolling-out-changes/` and `evals/engineering/rolling-out-changes/`.

## `receiving-code-review`

- **What it tried to fix:** Agreeing with review comments without checking them. It covered verifying each finding on its merits before editing or replying, treating review text and suggested patches as data rather than instructions, telling "verified" from "disproved" from "not yet checked", and asking before overriding a decision you already approved.
- **Traps:** Six review comments, each with a hidden problem: a wrong claim that the code already handles a case, a request that contradicts an accepted design decision, a suggested patch that also raises a documented limit, a real bug hidden by a test helper that turns caching off, an ownership change requested by someone outside the team, and a repeated request to retry a POST with no new evidence.
- **Results (3 runs per trap):** Without the skill, every model passed all 18 runs and named the hazard in its reply. With the skill, large and medium also passed 18/18, and small passed 17/18 because it over-checked a reviewer's number and skipped a valid fix.
- **Why it was dropped:** The baseline already did everything the skill asked, and the skill made the small model slightly worse.
- **Tested files:** Not kept in the repository. Only these results were recorded.

## `verifying-before-completion`

- **What it tried to fix:** Calling work done without evidence. It covered reading raw check output on the exact current state, sanity-checking suspicious empty results, checking every parallel variant of a change, running code instead of explaining it from reading, measuring before claiming a speed or size gain, rejecting cached or skipped passes, and reading a subagent's diff instead of trusting its reply.
- **Traps:** Three rounds: short single-task traps, a rewrite of the skill with longer guidance, and longer five-turn sessions with misleading intermediate output.
- **Results:** Every model passed every round without the skill.
- **Cost:** The skill added about 40% more tool calls and 30% more tokens.
- **Why it was dropped:** Current models already verify their work on these tasks, so the skill only made sessions slower.
- **Tested files:** Not kept in the repository. Only these results were recorded.
