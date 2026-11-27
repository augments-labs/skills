# Contributing to Augments Labs Skills

Thanks for contributing. Shared authoring rules, size caps, and branching
conventions live in [`AGENTS.md`](AGENTS.md); this guide covers the practical
workflow for contributors.

## Workflow

1. Branch from `dev` (for example `task/<topic>`) and open your PR against
   `dev`. Never commit directly to `dev` or `main`, and do not bump versions or
   `CHANGELOG.md` headings in ordinary PRs (see [`RELEASING.md`](RELEASING.md)).
2. Edit canonical sources under `skills/<pack>/` or `hooks/<pack>/`, never the
   generated bundles under `plugins/<plugin>/`. Run `bash scripts/sync-plugins.sh`
   after changing promoted skills or hooks.
3. Run the deterministic checks before pushing (CI runs the same gates):

```bash
bash scripts/validate.sh --strict
bash evals/bin/check
```

`scripts/validate.sh --strict` checks frontmatter, size ceilings, token budgets
(including the README table), cross-skill trigger collisions, dangling
references, and `scripts/sync-plugins.sh --check`.

To run these automatically on commit, install the optional pre-commit hook
(`--remove` undoes it):

```bash
bash scripts/install-git-hooks.sh
```

## Evaluations (`evals/`)

All behavior and triggering evals live under `evals/` and never ship in
`plugins/`. See [`evals/README.md`](evals/README.md) for commands and schemas.

- **Staging:** Draft new skills in `skills/in-progress/<name>/` and iterate
  freely before promoting.
- **Promotion or edits:** Any change under `skills/<pack>/<name>/` requires an
  updated `evals/results/<pack>/<name>.json` written by `evals/bin/report`,
  matching the skill's git tree and description hash with at least one model
  passing behavior controls (`>= 3` runs/case) and triggering (`>= 3` runs).
  Each skill keeps one compact JSON file overwritten in place; git history keeps
  older runs. Typos and non-behavioral fixes can use the `no-eval` label.
- **Abandoning a skill:** When a draft shows no real gain over `none`, land
  the exact draft and eval cases that were tested on `dev` in their own PR
  (squash merges drop commits that exist only on a branch). Then, in a
  follow-up PR, remove them and add an entry to
  [`docs/reference/abandoned-skills.md`](docs/reference/abandoned-skills.md)
  with what the skill tried to fix, the traps, results per tier, the cost,
  why it was dropped, and the commit that holds the tested files. Keep
  `skills/deprecated/` for skills that shipped and were later retired.
- **Neighbor routing checks:** When adding or editing an auto-triggered skill
  whose triggers could overlap with another skill, run a fast 1-turn routing
  check with `evals/bin/triggering --with-skills <neighbor>` instead of
  re-running full behavioral sessions for unchanged skills.
- **No live models in CI:** Never commit `evals/workspaces/` or transcripts. CI
  runs `evals/bin/check` (syntax + `fake-cli` offline tests) only.

## Multi-harness packaging

Every harness installs from a generated per-pack bundle under `plugins/<plugin>/`
(or a root entry point pointing into it). Keeping canonical skills under
`skills/<pack>/<name>/` and generating flat bundles under `plugins/<plugin>/`
keeps staging drafts, evaluation files, and separate domain packs out of user
installs.

| Harness | Packaging surface | Notes |
| --- | --- | --- |
| Claude Code | `.claude-plugin/marketplace.json` -> `plugins/<plugin>/` | Strict `owner` schema (`name`, optional `email`, no `url`); reads `skills/` and `hooks/hooks.json` |
| Codex CLI | `.agents/plugins/marketplace.json` -> `plugins/<plugin>/` | Reads `skills/` and `hooks/codex-hooks.json` declared in `.codex-plugin/plugin.json` |
| Antigravity | `plugins/<plugin>/.antigravity-plugin/plugin.json` | Reads `skills/` and root `hooks.json` |
| Cursor | `plugins/<plugin>/.cursor-plugin/plugin.json` | Local copy into `~/.cursor/plugins/local/<plugin>/`; `"hooks": {}` keeps Claude hooks out |
| Devin | `plugins/<plugin>/.devin-plugin/plugin.json` | Finds `skills/` by convention; hook adapter stays inert when `DEVIN_PROJECT_DIR` is set |
| Grok Build | `.grok-plugin/marketplace.json` -> `plugins/<plugin>/.grok-plugin/plugin.json` | `"hooks": []` keeps hook files out; root `.grok-plugin/plugin.json` scopes root installs to the root pack |
| Kimi Code | Root `.kimi-plugin/plugin.json` or bundle `.kimi-plugin/plugin.json` | Lists `skills` only (no hooks) |
| Muse Code | `.claude-plugin/marketplace.json` -> `plugins/<plugin>/.muse-plugin/plugin.json` | Lists each skill explicitly under `capabilities.skills` (no hooks) |
| Hermes | `plugins/<plugin>/plugin.yaml` + `__init__.py` | Installs bundle subdirectory; skills only |
| OpenCode 2.x | Root `index.js` -> `plugins/<plugin>/index.js` | Zero npm deps; skills only |
| pi | Root `package.json` (`pi.skills`) | Points to `./plugins/engineering-skills/skills`; skills only |
| `npx skills add` | `plugins/<plugin>/skills/<name>/SKILL.md` | Flat skill folders only |

A new pack needs a `pack_meta` entry in `scripts/sync-plugins.sh` and entries in
`.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`.

To smoke-test plugin installation locally (no model call, needs the harness CLI
and `jq`):

```bash
bash tests/run-plugin-smoke.sh --harness claude-code
```

## Hooks (`hooks/<pack>/`)

Each hook entry script (`hooks/<pack>/<hook>.sh`) takes the harness name
(`claude-code`, `codex`, or `antigravity`) and delegates to shared checks under
`hooks/<pack>/lib/`:

- `adapter.sh` normalizes harness events, steps aside under Devin (`DEVIN_PROJECT_DIR`), and formats deny/allow answers.
- `checks.sh` implements the guard rules.
- `walk.sh` and `shell.awk` split command lines into simple commands.
- `json.awk` parses event payloads without `jq`.

Try a check without a harness (exits 0 to allow, 2 to deny):

```bash
bash hooks/engineering/lib/check.sh --hook guard-destructive-git --tool shell --command 'git reset --hard'
```

Hook implementation rules:

- Bash 3.2 and POSIX `awk` only (portable across Linux, macOS, and Windows Git
  Bash; no `jq` or Python). Keep subprocess forks low.
- Allow unparseable events with a note on stderr; ignore malformed `policy.json`
  so broken config never grants a bypass.
- Read bypasses only from `~/.config/augments-skills/policy.json`. Repo-local
  `.augments-labs-config.json` may only add protected branches.
- On Antigravity, answer `{}` to allow (never `"decision": "allow"`, which
  bypasses the harness's own permission prompt).

Run `bash tests/run-engineering-hooks.sh` after any hook change, and update
[`docs/hooks.md`](docs/hooks.md) when user-visible behavior changes.
