# Skill catalogue

This page lists every promoted skill currently shipped in `engineering-skills` (`0.3.0`). All five are auto-triggered skills, evaluated against a no-skill baseline with hooks turned off. Exact tested model IDs are listed in each JSON record and the [`README.md`](../../README.md) scoreboard.

Drafts that did not beat the baseline are listed in [Skills we tested and left out](abandoned-skills.md).

## `changing-a-live-schema`

- **Path:** `skills/engineering/changing-a-live-schema/SKILL.md`
- **Support files:** None
- **Triggers on:** Adding, renaming, retyping, or removing a column, table, index, or constraint, writing a backfill or data migration, or adding a migration file for a database that serves production, even when the change looks like one `ALTER` statement.
- **Skips:** Databases nothing serves yet (a new project, a test-only database), questions that change nothing, and code changes that touch no schema.
- **Measured results:** small 100% vs 61%, medium 100% vs 83%, large 100% vs 78%; controls pass; triggering 36/36. Record: [`evals/results/engineering/changing-a-live-schema.json`](../../evals/results/engineering/changing-a-live-schema.json).

## `debugging`

- **Path:** `skills/engineering/debugging/SKILL.md`
- **Support files:** `references/feedback-loop-options.md` (loaded when no obvious reproduction loop exists), `references/probabilistic-evidence.md` (loaded for intermittent, timing-dependent, or environment-specific failures)
- **Triggers on:** Bugs, failing or flaky tests, CI failures, crashes, regressions after a merge or upgrade, rejected input, hangs, memory leaks or OOMs, and wrong or missing output where the diagnosis is left to the agent.
- **Skips:** Already-diagnosed fixes where you spelled out the change (typos, missing imports, known null fallbacks), live user-facing outages (contain first), and post-incident reviews.
- **Measured results:** small 93% vs 78%, medium 100% vs 89%, large 100% vs 96%; controls pass; triggering 31/31. Record: [`evals/results/engineering/debugging.json`](../../evals/results/engineering/debugging.json).

## `finishing-a-branch`

- **Path:** `skills/engineering/finishing-a-branch/SKILL.md`
- **Support files:** None
- **Triggers on:** Pushing, opening or describing a pull request, merging, squashing or rewriting history, and deleting branches or worktrees, including requests to finish, ship, wrap up, or clean up a branch.
- **Skips:** Plain commits, creating branches, and questions about git.
- **Measured results:** small 100% vs 71%, medium 100% vs 100%, large 100% vs 86%; controls pass; triggering 36/36. Record: [`evals/results/engineering/finishing-a-branch.json`](../../evals/results/engineering/finishing-a-branch.json).

## `test-driven-development`

- **Path:** `skills/engineering/test-driven-development/SKILL.md`
- **Support files:** None
- **Triggers on:** Adding behavior with multiple rules or edge cases (features, endpoints, parameters, validators, guards, locks) or refactoring, splitting, moving, or rewriting code whose observable behavior must stay identical.
- **Skips:** One-condition tweaks (scales down to one test in the same pass), docs, comments, renames, formatting, config edits, and bug reports with unknown causes.
- **Measured results:** small 100% vs 57%, medium 100% vs 38%, large 100% vs 81%; controls pass; triggering 36/36. Record: [`evals/results/engineering/test-driven-development.json`](../../evals/results/engineering/test-driven-development.json).

## `writing-skills`

- **Path:** `skills/engineering/writing-skills/SKILL.md`
- **Support files:** `scripts/check-skill.sh` (portable validator run on a skill folder before finishing)
- **Triggers on:** Creating, editing, trimming, or repairing a `SKILL.md` and its directory, fixing a skill that never loads or triggers, adding support files and links, or turning a runbook or recurring repo failures into a project skill.
- **Skips:** Following an existing skill, performing the underlying task a skill describes, and editing non-skill docs like a README or plain runbook.
- **Measured results:** small 100% vs 75%, medium 100% vs 100%, large 100% vs 92%; controls pass; triggering 36/36 on medium and large, 32/36 on small. Record: [`evals/results/engineering/writing-skills.json`](../../evals/results/engineering/writing-skills.json).

## Context budget

With all five promoted skills installed:

- Combined auto-triggered descriptions: 2,619 characters (roughly 655 tokens), against a pack ceiling of 3,400 characters.
- Individual skill bodies: 80 to 137 lines each, well below the 200-line and 8,000-byte per-skill ceiling.
