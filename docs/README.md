# Documentation

These pages are for people who install `augments-labs/skills` and work with a coding agent that has it loaded. They explain how to install the pack, what each skill and hook does in a real session, and what still stays up to you.

If you want to change the repository itself, read [`CONTRIBUTING.md`](../CONTRIBUTING.md) and [`AGENTS.md`](../AGENTS.md) instead. Those files cover authoring rules, plugin syncing, tests, and evaluations.

## Where to start

1. Install `engineering-skills` for your agent using [Installing, updating, and removing](guides/installing.md).
2. Walk through [Your first session](guides/first-session.md) to confirm that the skills and hooks loaded properly.
3. Read the guide for the kind of work you are doing next.

## Guides

Each guide walks through a concrete workflow with example prompts and explains what the agent does at each step.

| Page | What it covers |
| --- | --- |
| [Installing, updating, and removing](guides/installing.md) | Setup, updates, and removal for all 11 supported harnesses plus `npx skills add` |
| [Your first session](guides/first-session.md) | Checking that skills and hooks are active, calling a skill by name, and knowing when skills stay quiet |
| [Fixing a bug](guides/fixing-a-bug.md) | Using `debugging` to reproduce failures, check test doubles, and fix the real root cause |
| [Writing tests first](guides/writing-tests-first.md) | Using `test-driven-development` for edge cases, red-green cycles, safe refactors, and catching weak tests |
| [Changing a live schema](guides/changing-a-schema.md) | Using `changing-a-live-schema` to split renames across deploys, keep old builds working, and keep locks and backfills short |
| [Authoring project skills](guides/authoring-project-skills.md) | Using `writing-skills` to turn team runbooks and recurring bugs into repo-local skills |
| [Engineering hooks](hooks.md) | What `guard-destructive-git` and `guard-protected-branch` block, what they allow, and how to configure bypasses |
| [Using the skills on another agent](guides/other-agents.md) | Installing the flat skill bundle on an agent outside the supported list |

## Concepts

Short explanations of the design choices behind the library.

| Page | What it explains |
| --- | --- |
| [How skills load](concepts/how-skills-load.md) | Progressive disclosure, description budgets, and why small tasks stay fast |
| [Skills and hooks](concepts/skills-and-hooks.md) | Why mechanical guardrails live in deterministic hooks while judgment lives in eval-backed skills |

## Reference

Quick lookup tables for the current `0.1.2` release.

| Page | What it holds |
| --- | --- |
| [Skill catalogue](reference/skills.md) | Every promoted skill, when it triggers, when it skips, and its measured eval results |
| [Supported agents](reference/agents.md) | What each of the 11 harnesses gets, whether hooks run, and known quirks |
| [Agent Skills conformance](reference/agent-skills-conformance.md) | How the pack follows the open Agent Skills format and where our own limits are stricter |
