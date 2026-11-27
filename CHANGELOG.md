# Changelog

All notable changes to `augments-labs/skills` are documented here. Entries follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Added [Skills we tested and left out](docs/reference/abandoned-skills.md),
  which explains why `containing-incidents`, `deprecating-apis`,
  `rolling-out-changes`, `receiving-code-review`, and
  `verifying-before-completion` are not in the pack, with what each tried to
  fix and its measured results.

## [0.2.0] - 2026-11-27

- Added `changing-a-live-schema`, which keeps every build serving during a
  rollout working when your agent changes a production database schema. It
  splits renames and removals across deploys, checks new columns against old
  readers, keeps locks and backfills short, and tests the previous build
  against the migrated database.

## [0.1.2] - 2026-11-26

- `debugging` now writes the code fallback you ask for when the cause is bad
  data, a permission, or infrastructure. It keeps the fallback to the inputs
  that fail today and still reports the upstream cause, instead of stopping
  to ask.
- `engineering-skills` now installs on Cursor and Devin (skills only), bringing
  support to 11 coding agents plus `npx skills add`.
- Added user documentation under `docs/` covering installation, first-session
  checks, per-skill guides, design concepts, the skill catalogue, the agent
  matrix, and conformance notes.
- Simplified the evaluation tooling and records: each promoted skill now keeps
  one compact JSON record under `evals/results/<pack>/<skill>.json`, triggering
  checks support `--with-skills` to test routing against neighboring skills, and
  refusal detection reads provider errors instead of agent prose.

## [0.1.1] - 2026-11-21

- `writing-skills` skill in the engineering pack: writes skills that load, with
  descriptions that name the situations people report, keeps every guard when
  trimming a skill, and calibrates a project skill's check script against the
  failures it must catch.

## [0.1.0] - 2026-11-21

- `engineering-skills` now installs on OpenCode 2.x, pi, Grok Build, Hermes,
  Kimi Code, and Muse Code, with the skills only. The hooks still run in Claude
  Code, Codex CLI, and Antigravity, and stay out of the other harnesses.
- `test-driven-development` skill in the engineering pack: writes tests before
  the code, pins the current behavior before a refactor, and plants likely
  mistakes to confirm the tests catch each one.

## [0.0.1] - 2026-11-21

- First release of the `engineering-skills` plugin for Claude Code, Codex CLI,
  Antigravity, and `npx skills add`.
- `debugging` skill: proves a bug's root cause with a runnable signal before
  patching, checks test doubles against the real implementation, and reverts
  earlier failed fixes before diagnosing, so fixes land on the real cause.
- `guard-destructive-git` and `guard-protected-branch` hooks: block commands
  that destroy unsaved work or write to protected branches, and tell the agent
  to ask you first.
