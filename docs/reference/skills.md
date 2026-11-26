# Skill catalogue

This page lists every promoted skill currently shipped in `engineering-skills` (`0.1.1`). All three are auto-triggered skills, evaluated against a no-skill baseline with hooks turned off.

## `debugging`

- **Path:** `skills/engineering/debugging/SKILL.md`
- **Support files:** `references/feedback-loop-options.md` (loaded when no obvious reproduction loop exists), `references/probabilistic-evidence.md` (loaded for intermittent, timing-dependent, or environment-specific failures)
- **Triggers on:** Bugs, failing or flaky tests, CI failures, crashes, regressions after a merge or upgrade, rejected input, hangs, memory leaks or OOMs, and wrong or missing output where the diagnosis is left to the agent.
- **Skips:** Already-diagnosed fixes where you spelled out the change (typos, missing imports, known null fallbacks), live user-facing outages (contain first), and post-incident reviews.
- **Measured results:** Haiku 93% vs 78%, Opus 100% vs 96%, Sonnet 100% vs 89%; controls pass; triggering 31/31. Record: [`evals/results/engineering/debugging.json`](../../evals/results/engineering/debugging.json).

## `test-driven-development`

- **Path:** `skills/engineering/test-driven-development/SKILL.md`
- **Support files:** None
- **Triggers on:** Adding behavior with multiple rules or edge cases (features, endpoints, parameters, validators, guards, locks) or refactoring, splitting, moving, or rewriting code whose observable behavior must stay identical.
- **Skips:** One-condition tweaks (scales down to one test in the same pass), docs, comments, renames, formatting, config edits, and bug reports with unknown causes.
- **Measured results:** Haiku 100% vs 57%, Opus 100% vs 81%, Sonnet 100% vs 38%; controls pass; triggering 36/36. Record: [`evals/results/engineering/test-driven-development.json`](../../evals/results/engineering/test-driven-development.json).

## `writing-skills`

- **Path:** `skills/engineering/writing-skills/SKILL.md`
- **Support files:** `scripts/check-skill.sh` (portable validator run on a skill folder before finishing)
- **Triggers on:** Creating, editing, trimming, or repairing a `SKILL.md` and its directory, fixing a skill that never loads or triggers, adding support files and links, or turning a runbook or recurring repo failures into a project skill.
- **Skips:** Following an existing skill, performing the underlying task a skill describes, and editing non-skill docs like a README or plain runbook.
- **Measured results:** Haiku 100% vs 75%, Opus 100% vs 92%, Sonnet 100% vs 100%; controls pass; triggering 36/36 on Opus and Sonnet, 32/36 on Haiku. Record: [`evals/results/engineering/writing-skills.json`](../../evals/results/engineering/writing-skills.json).

## Context budget

With all three promoted skills installed:

- Combined auto-triggered descriptions: 1,801 characters (roughly 451 tokens), against a pack ceiling of 3,400 characters.
- Individual skill bodies: 114 to 137 lines each, well below the 200-line and 8,000-byte per-skill ceiling.
