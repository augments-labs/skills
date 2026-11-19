# Augments Labs Skills

Focused, eval-backed Agent Skills and deterministic guardrails for coding agents, built on the open [Agent Skills](https://agentskills.io) standard and organized into domain packs.

Most skill libraries for coding agents fail in the same ways:

- Dozens of auto-triggered skills overflow harness listing budgets.
- Heavy routers burn thousands of tokens on a one-line edit.
- Agents anchor on custom metadata ledgers instead of the engineering task.
- There is no evidence that any skill beats a modern frontier model working without it.

This repository exists to solve those problems without giving up real engineering discipline.

## Table of contents

- [Why this repository exists](#why-this-repository-exists)
- [How it works](#how-it-works)
- [Packs](#packs)
- [Context cost and measured evidence](#context-cost-and-measured-evidence)
- [Installation](#installation)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)
- [Acknowledgements](#acknowledgements)

## Why this repository exists

Frontier models improve every month. Teaching an agent textbook coding procedures it already performs unprompted wastes context and degrades its judgment. At the same time, real software engineering is defined by constraints, invariants, and external proof rather than free-form code generation. That means:

- Seeing a test fail for the right reason before writing the fix.
- Verifying empty or zero outputs with a positive control, and running code instead of guessing from reading it.
- Checking every parallel variant and sibling call site instead of fixing one branch.
- Evolving a live database schema in expand, dual-write, backfill, and contract phases so rollback keeps working.
- Guarding every path behind a runtime feature switch, and containing a live outage before reading source code.
- Stopping at irreversible or external-authority decisions that belong to a human.

The library is designed to adapt as models get stronger:

1. Hooks enforce mechanical invariants, and skills teach non-obvious judgment. Hard stops that must hold every time (destructive git guards, protected-branch guards) belong in deterministic tool hooks instead of pages of shouting prose.
2. No always-on router bloat. Small tasks pay near-zero overhead. A lean auto-triggered core covers real engineering risk. Heavier workflows run only when you explicitly invoke them, and they never silently chain into each other.
3. No custom library bureaucracy. There are no hidden metadata directories, append-only custom ledgers, or 500-word templates. Evidence lives in native artifacts that engineers already read: git commits, raw check output, tests, and PR descriptions.
4. Domain packs stay separate. `skills/engineering/` ships as `engineering-skills` and is kept apart from future domain packs (such as `skills/games/`).
5. Skills are measured from the first one and retired when models catch up. Every promoted skill passes a 3-arm evaluation (`full` vs `~150-word distilled` vs `no skill`, including no-harm control tasks) plus a triggering check inside `evals/`. If the distilled version matches the full body, we ship the distilled version. When a future model closes the gap and a skill's delta drops to noise, the skill moves to `skills/deprecated/` with the record showing why.

## How it works

Each pack combines four layers:

1. Deterministic hooks, which cost 0 context tokens on happy paths. On hook-capable harnesses, per-harness `PreToolUse` / `PostToolUse` adapters enforce mechanical invariants outside the prompt. On harnesses without pre-tool hooks, a compact standing-rules fallback carries the same invariants.
2. A lean auto-triggered core. Its descriptions are short and budgeted so that triggers and `Skip` clauses remain visible inside harness listing limits.
3. Explicit user-invoked workflows. These are marked with `disable-model-invocation: true` (plus manual-only descriptions for strict spec-only harnesses) so heavy workflows never hijack small edits.
4. Project-local verification. This turns your repository's own domain invariants and recurring failure modes into repo-local verification skills and deterministic checks.

## Packs

Skills live under `skills/<pack>/` and ship as self-contained plugin bundles under `plugins/<plugin>/`:

| Pack | Plugin address | Status | Focus |
| --- | --- | --- | --- |
| **Engineering** (`skills/engineering/`) | `engineering-skills@augments-labs` | Pre-release (`0.0.0`, building toward `v0.0.1`) | Eval-backed engineering constraints, verification, debugging, production-safety, and project-local checks |
| **Staging** (`skills/in-progress/`) | *(not bundled)* | Experimental | Candidate skills undergoing 3-arm and triggering evaluation before promotion |
| **Retired** (`skills/deprecated/`) | *(not bundled)* | Archived | Skills retired once frontier models close the gap |

Additional domain packs (such as `skills/games/`) will ship as separate plugins, so pack-capable harnesses only load the domains you install.

## Context cost and measured evidence

Every promoted skill body under `skills/engineering/` is capped at 200 lines, 2,000 approximate tokens, and 8,000 bytes. Every promoted skill also requires committed 3-arm and triggering records under `evals/results/`.

<!-- token-budget-table:start -->
| Surface (`engineering-skills`) | Skills | Words | Approx tokens |
| --- | --- | --- | --- |
| Pre-release skeleton (no promoted skills yet) | 0 | 0 | 0 |
<!-- token-budget-table:end -->

<!-- eval-scoreboard:start -->
| Skill | Arm shipped | Pass rate (`shipped` vs `none`) | Control delta (non-trigger / small fix) | Token delta | Model & date | Record |
| --- | --- | --- | --- | --- | --- | --- |
| *(Pending first evaluated promotion for `v0.0.1`)* | n/a | n/a | n/a | n/a | n/a | n/a |
<!-- eval-scoreboard:end -->

## Installation

> **Pre-release notice (`0.0.0`):** This repository is still pre-release scaffolding. Installable plugin bundles under `plugins/engineering-skills/` will ship starting with `v0.0.1`, once the first skill and hooks pass evaluation.

### Claude Code

```text
/plugin marketplace add augments-labs/skills
/plugin install engineering-skills@augments-labs
```

### Codex CLI

```bash
git clone https://github.com/augments-labs/skills.git
codex plugin marketplace add /path/to/skills
codex plugin add engineering-skills@augments-labs
```

### Antigravity

```bash
agy plugin install https://github.com/augments-labs/skills/tree/main/plugins/engineering-skills
```

### Cursor

```bash
git clone https://github.com/augments-labs/skills.git /tmp/augments-skills
cp -R /tmp/augments-skills/plugins/engineering-skills ~/.cursor/plugins/local/engineering-skills
```

### Devin

```bash
devin plugins install augments-labs/skills#plugins/engineering-skills
```

### Skill-only install (`npx skills`)

```bash
npx skills add augments-labs/skills/plugins/engineering-skills
```

> Note: `npx skills add` installs `SKILL.md` files only, without deterministic hooks. For hook enforcement, install through your harness's plugin mechanism above. [`docs/hooks.md`](docs/hooks.md) lists what the hooks block and how to turn them off.

### Additional harnesses (OpenCode, pi, Kimi Code, Hermes, Grok Build, Muse Code)

Support for OpenCode (1.x/2.x), pi, Kimi Code, Hermes, Grok Build, and Muse Code will be documented in [`docs/`](docs/README.md), with verified install commands, as each harness adapter passes live smoke tests. On Hermes, answer "no" if you are prompted about `package.json` Node dependencies. Zero dependencies are required. Harnesses that install from the repository root load `engineering-skills` by default.

## Documentation

User documentation lives under [`docs/`](docs/README.md). Maintainer internals, evaluation rules, adapter contracts, and release procedures live in [`CONTRIBUTING.md`](CONTRIBUTING.md), [`AGENTS.md`](AGENTS.md), and [`RELEASING.md`](RELEASING.md).

## Contributing

Contributions are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request. The short version:

1. Branch from `dev` (`main` is reserved for releases and hotfixes).
2. Keep one logical change per PR.
3. Run the deterministic checks before committing.
4. For any promotion or edit under `skills/<pack>/`, include its 3-arm eval record, its triggering eval record, or both under `evals/results/`.

## Security

This repository distributes executable hooks and adapter scripts. See [`SECURITY.md`](SECURITY.md) for how to report vulnerabilities privately.

## License

MIT. See [`LICENSE`](LICENSE).

## Acknowledgements

This library draws on ideas and lessons from across the coding-agent community:

- [SDLC skills](https://github.com/augments-labs/sdlc-skills): our archived predecessor. Its production-engineering constraints, verification discipline, and multi-harness work directly inspired `engineering-skills`.
- [Agent Skills](https://agentskills.io): the open `SKILL.md` specification and evaluation methodology.
- [Superpowers](https://github.com/obra/superpowers): disciplined software-engineering workflows for coding agents.
- [pstack](https://github.com/backnotprop/pstack): opt-in heavy orchestration, formal state modeling, blast-radius verification, anti-slop discipline, and project-local verification skills.
- [Matt Pocock skills](https://github.com/mattpocock/skills): modular skill buckets, `disable-model-invocation` boundaries, and structured pre-code requirements interviews.
- [Ponytail](https://github.com/DietrichGebert/ponytail): the pre-code simplification decision ladder.
