# Changelog

All notable changes to `augments-labs/skills` are documented here. Entries follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
