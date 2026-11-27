# Augments Labs Skills

Focused, eval-backed Agent Skills and deterministic guardrails for coding agents, built on the open [Agent Skills](https://agentskills.io) standard and organized into domain packs.

## Why this repository exists

Most coding-agent skill libraries bloat context with dozens of auto-triggered procedures, custom metadata ledgers, and unmeasured advice that modern frontier models already follow unprompted.

This library takes a leaner approach:

1. **Hooks enforce mechanical invariants; skills teach non-obvious judgment.** Hard stops (destructive git commands, protected-branch writes) live in deterministic tool hooks costing 0 context tokens on happy paths.
2. **Small, budgeted auto-triggered core.** Skill bodies stay under 200 lines and 8,000 bytes, and pack descriptions stay budgeted so small tasks pay near-zero overhead.
3. **No custom library bureaucracy.** No hidden metadata directories, custom ledgers, or fill-in-every-section templates. Evidence lives in native artifacts: git commits, raw check output, tests, and PR descriptions.
4. **Measured before shipping.** Every promoted skill is evaluated against `none` (no skill) on realistic multi-file traps plus trivial control tasks, and retired if newer models close the gap.

## Packs

Canonical skills live under `skills/<pack>/` and build into self-contained plugin bundles under `plugins/<plugin>/`:

| Pack | Plugin address | Status | Focus |
| --- | --- | --- | --- |
| **Engineering** (`skills/engineering/`) | `engineering-skills@augments-labs` | Pre-1.0 (`0.1.2`) | Eval-backed debugging, TDD, skill authoring, and git guardrail hooks |

## Context cost and measured evidence

Every promoted skill body under `skills/engineering/` is capped at 200 lines, 2,000 approximate tokens, and 8,000 bytes, with a compact summary record under `evals/results/<pack>/<skill>.json`.

<!-- token-budget-table:start -->
| Surface (`engineering-skills`) | Skills | Words | Approx tokens |
| --- | --- | --- | --- |
| Auto-triggered descriptions (2296 chars) | 4 | n/a | 574 |
| User-invoked descriptions (0 chars) | 0 | n/a | 0 |
| Promoted skill bodies (if all loaded) | 4 | 4051 | 5839 |
<!-- token-budget-table:end -->

<!-- eval-scoreboard:start -->
| Skill | Pass rate (`skill` vs `none`) | Controls | Triggering | Updated | Record |
| --- | --- | --- | --- | --- | --- |
| `engineering/changing-a-live-schema` | claude-haiku-5-5 100% vs 61% · claude-opus-5-5 100% vs 78% · claude-sonnet-5-5 100% vs 83% | pass | 36/36 | 2026-11-27 | [changing-a-live-schema.json](evals/results/engineering/changing-a-live-schema.json) |
| `engineering/debugging` | claude-haiku-5-5 93% vs 78% · claude-opus-5-5 100% vs 96% · claude-sonnet-5-5 100% vs 89% | pass | 31/31 | 2026-11-21 | [debugging.json](evals/results/engineering/debugging.json) |
| `engineering/test-driven-development` | claude-haiku-5-5 100% vs 57% · claude-opus-5-5 100% vs 81% · claude-sonnet-5-5 100% vs 38% | pass | 36/36 | 2026-11-21 | [test-driven-development.json](evals/results/engineering/test-driven-development.json) |
| `engineering/writing-skills` | claude-haiku-5-5 100% vs 75% · claude-opus-5-5 100% vs 92% · claude-sonnet-5-5 100% vs 100% | pass | claude-haiku-5-5 32/36 · claude-opus-5-5 36/36 · claude-sonnet-5-5 36/36 | 2026-11-21 | [writing-skills.json](evals/results/engineering/writing-skills.json) |
<!-- eval-scoreboard:end -->

## Installation

> **Pre-1.0 notice (`0.1.2`):** `engineering-skills` ships four evaluated skills (`changing-a-live-schema`, `debugging`, `test-driven-development`, `writing-skills`) and two hooks (`guard-destructive-git`, `guard-protected-branch`).

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
git clone https://github.com/augments-labs/skills.git
mkdir -p ~/.cursor/plugins/local/engineering-skills
cp -R skills/plugins/engineering-skills/. ~/.cursor/plugins/local/engineering-skills/
```

### Devin

```bash
devin plugins install augments-labs/skills#plugins/engineering-skills
```

### Grok Build

```bash
grok plugin marketplace add augments-labs/skills
grok plugin install engineering-skills
```

### Kimi Code

```text
/plugins install https://github.com/augments-labs/skills/archive/refs/heads/main.zip
```

### Muse Code

```bash
muse plugins marketplace add augments-labs https://github.com/augments-labs/skills.git
muse plugins install engineering-skills@augments-labs
```

### Hermes

```bash
hermes plugins install augments-labs/skills/plugins/engineering-skills --enable
```

### OpenCode 2.x

```bash
opencode plugin add git+https://github.com/augments-labs/skills.git
```

### pi

```bash
pi install git:github.com/augments-labs/skills
```

### Skill-only install (`npx skills`)

```bash
npx skills add augments-labs/skills/plugins/engineering-skills
```

Hooks run in Claude Code, Codex CLI, and Antigravity. Every other install loads skills only. See [Installing, updating, and removing](docs/guides/installing.md) and [Engineering hooks](docs/hooks.md) for details, updates, and bypass configuration.

## Documentation & Contributing

- User documentation: [`docs/`](docs/README.md) (guides, concepts, skill catalogue, agent matrix, and hooks reference)
- Contributing and evals: [`CONTRIBUTING.md`](CONTRIBUTING.md), [`AGENTS.md`](AGENTS.md), [`evals/README.md`](evals/README.md), and [`RELEASING.md`](RELEASING.md)
- Security: [`SECURITY.md`](SECURITY.md)
- License: [MIT](LICENSE)

## Acknowledgements

This library draws on ideas and lessons from across the coding-agent community:

- [SDLC skills](https://github.com/augments-labs/sdlc-skills): our archived predecessor.
- [Agent Skills](https://agentskills.io): the open `SKILL.md` specification and evaluation methodology.
- [Superpowers](https://github.com/obra/superpowers): disciplined software-engineering workflows for coding agents.
- [pstack](https://github.com/backnotprop/pstack): opt-in heavy orchestration, blast-radius verification, and project-local verification skills.
- [Matt Pocock skills](https://github.com/mattpocock/skills): modular skill buckets and `disable-model-invocation` boundaries.
- [Ponytail](https://github.com/DietrichGebert/ponytail): the pre-code simplification decision ladder.
