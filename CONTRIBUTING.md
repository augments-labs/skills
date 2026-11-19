# Contributing to Augments Labs Skills

Thank you for contributing. This guide is written for people; coding agents read
[`AGENTS.md`](AGENTS.md), which encodes the same rules as direct instructions.

## Before you start

- **Solve a real failure.** Name the concrete mistake, production footgun, or
  contract gap the change addresses. "It could theoretically help" is not enough.
- **Search open and closed issues and PRs first.**
- **Respect pack boundaries.** General engineering skills live in
  `skills/engineering/` and bundle into `plugins/engineering-skills/`; future
  domain packs live in their own `skills/<pack>/` and `plugins/<plugin>/`. Every
  new skill starts in `skills/in-progress/` until its evals pass.
- **"No skill is needed here" and retiring a skill are valid outcomes.**

## Branching and making a change

1. Fork or clone the repository and create your own branch from `dev`, for
   example `task/<topic>`. Never commit or push to `dev` or `main` directly;
   branch protection rejects it. `main` is reserved for releases and hotfixes,
   and the `release/`, `hotfix/`, and `backmerge/` prefixes are reserved for
   maintainers.
2. Open your pull request against `dev`. It is squash-merged once the required
   checks pass, and a branch in this repository is deleted automatically after
   the merge. On a fork, delete your branch yourself.
3. Keep one logical change per pull request.
4. Edit canonical sources under `skills/<pack>/` or `hooks/<pack>/`, never the
   generated plugin bundles under `plugins/<plugin>/`. Run
   `bash scripts/sync-plugins.sh` after editing promoted skills or hooks.
5. Follow the authoring rules in [`AGENTS.md`](AGENTS.md): strict Agent Skills
   conformance, gerund/activity kebab-case names (`debugging`, `verifying`,
   `changing-a-live-schema`, `finishing-a-branch`, `reviewing-code`) with no
   built-in slash-command shadowing (e.g., `review`, `simplify`, `plan`), body
   size caps (`<= 200` lines / `<= 2,000` tokens / `<= 8,000` bytes), per-pack
   description caps (`<= 3,400` auto / `<= 2,400` user / `<= 5,800` combined),
   no custom metadata ledgers, no external references, no vendor model names in
   shipped content, and zero third-party runtime dependencies.
6. Keep `docs/` strictly for user documentation in plain second person. Put
   maintainer internals, adapter quirks, and test notes here in
   `CONTRIBUTING.md`.
7. Never bump versions or add `CHANGELOG.md` version headings in an ordinary
   contribution PR (see [`RELEASING.md`](RELEASING.md)).

## Running deterministic checks

Run locally before pushing (CI runs the same gates):

```bash
bash scripts/validate.sh --strict
bash scripts/token-budget.sh --check
bash scripts/validate-trigger-collisions.sh --strict
bash evals/bin/check
```

`scripts/validate.sh` also runs `bash scripts/sync-plugins.sh --check`, which
fails when `plugins/<plugin>/` differs from what `skills/<pack>/` and
`hooks/<pack>/` produce, and a dangling-reference check: promoted and
in-progress skills may name only promoted skills, and only support files that
exist inside the skill. To run these checks on every relevant commit, install
the optional pre-commit hook (`--remove` undoes it):

```bash
bash scripts/install-git-hooks.sh
```

## Evaluations (`evals/`)

All behavior and triggering evaluations live in `evals/` at the repository root
so eval cases stay in lockstep with the skills they test, while remaining
excluded from all generated plugin bundles under `plugins/`.

- **Staging (`skills/in-progress/`):** Iterate freely without blocking CI.
- **Hooks held constant:** Skill eval runs disable hooks across every arm
  (`full`, `distilled`, `none`) so skill deltas are never confounded with hook
  enforcement. Hooks have their own unit and live tests.
- **Promotion (`skills/in-progress/` -> `skills/<pack>/`):** Requires:
  1. A **3-arm behavior benchmark** (`full`, `distilled`, `none`) with `>= 3`
     scored runs per eval case across realistic multi-file adversarial tasks
     plus denominator-safe anti-ceremony controls (non-triggering trivial tasks:
     0 skill loads, 0 unrequested files, `<= +1` tool call; small in-scope
     fixes: 0 regression, `<= +2` tool calls, `<= +1` turn, bounded output
     tokens), zero indeterminate runs, and zero assertions awaiting review.
     `arms.<shipped_arm>.skill_tree` matches the **shipped arm** (`full` or
     `distilled`). If `distilled` matches `full` and beats `none`, ship
     `distilled`.
  2. A **triggering record** (`train` / `validation` / `holdout` splits, `>= 3`
     runs, zero inconclusive queries) for **auto-triggered skills**. Explicit
     user-invoked skills (`disable-model-invocation: true`) are exempt from
     positive-triggering splits, but MUST pass a negative-triggering check on
     spec-only harnesses confirming they do not self-fire on routine prompts.
- **Editing a promoted skill:** Requires a before/after (`full` vs `old_skill`)
  record for body/reference/asset changes, and a triggering record for
  description changes on auto-triggered skills, named as
  `Eval record: evals/results/<dir>` in the PR body.
- **Anti-gaming & self-attestation:** Changes to `evals/<pack>/<name>/**`
  (assertions, queries, fixtures, verifiers, or `distilled/SKILL.md`) should
  land separately from skill edits; touching both in one PR fails CI unless a
  maintainer applies `eval-assertion-reviewed`. A PR editing
  `.github/workflows/eval-record.yml` or `scripts/check-eval-record.sh` cannot
  attest its own skill edit.
- **Retirement:** When a newer frontier model closes the gap (`shipped - none`
  drops to noise), move the skill to `skills/deprecated/` alongside the eval
  record.
- **Never commit `evals/workspaces/` or raw transcripts**, and **never run live
  models in CI**.

## Multi-harness adapters

Pack-capable harnesses install from generated self-contained per-pack bundles
under `plugins/<plugin>/` (with root marketplace manifests for Claude Code and
Codex). Harnesses whose native installer only reads the repository root
(OpenCode, Kimi Code, Hermes) load `engineering-skills` by default until those
harnesses support subpath or multi-pack plugin installation.

Because tool names, `stdin` schemas, and deny protocols differ across harnesses
(for example, `Bash`/`Edit`/`Write` with `exit 2` vs `apply_patch` vs
`run_command` with JSON `decision: "deny"`), hook enforcement uses thin
per-harness adapters over shared check logic rather than assuming one universal
hook schema.

| Harness | Packaging surface | Known constraints |
| --- | --- | --- |
| Claude Code | `.claude-plugin/marketplace.json` -> `plugins/<plugin>/` | Strict `marketplace.json` owner schema (`name`, optional `email`, no `url`); discovers `skills/` and `hooks/hooks.json` at the plugin root; `PreToolUse`/`PostToolUse` hooks |
| Codex CLI | `.agents/plugins/marketplace.json` -> `plugins/<plugin>/` | Manifest names component paths (`skills`, `hooks` -> `hooks/codex-hooks.json`); installs into `$CODEX_HOME/plugins/cache/`; edits use `apply_patch` |
| Antigravity | `plugins/<plugin>/.antigravity-plugin/plugin.json` | Reads components from the plugin root only: hooks from root `hooks.json` (one named entry per hook; commands run in the plugin folder, and older builds do not set `${PLUGIN_ROOT}`), never `.antigravity-plugin/rules/` or `hooks/hooks.json`; check with `agy plugin validate --json` |
| Cursor | `plugins/<plugin>/` (cloned/copied locally) | Rejects symlinks outside `~/.cursor/plugins/local/`; auto-loads any `rules/` at plugin root |
| Devin | `plugins/<plugin>/.devin-plugin/plugin.json` | No `skills` field in manifest; no `AGENTS.md` at plugin root; hooks fail open; tool names `exec`/`edit`/`write` |
| OpenCode (1.x/2.x) | Root `index.js` + `package.json` -> plugin JS | Single module supports 1.x named exports + 2.x `default.setup(ctx)` + `default.id`; zero npm deps |
| pi | Per-pack `plugins/<plugin>/package.json` (`pi` key) | Keeps `pi install .../plugins/<plugin>` pack-isolated |
| Grok Build | `plugins/<plugin>/` + `$GROK_HOME/rules/` | Tool events support `additionalContext`; `SessionStart` discarded on 1.0.40 |
| Kimi Code | `.kimi-plugin/plugin.json` | No compaction event; subagents need full file paths |
| Hermes | `.hermes-plugin/` | No root `plugin.yaml`/`plugin.json`; system-prompt sections `<= 4k` each, `<= 8k` total; user answers "no" to root `package.json` Node-dep prompt |
| `npx skills add` | `plugins/<plugin>/skills/<name>/SKILL.md` (flat) | Skills only, no hooks; the smoke driver pins the CLI version and disables its telemetry |
| Muse Code | `.muse-plugin/plugin.json` + `scripts/install-muse-skills.sh` | 1.3.0 installs individual skills via CLI (`--pack engineering`) |

`scripts/sync-plugins.sh` maps `hooks/<pack>/config/{claude-code,codex,antigravity}.json`
to the path each harness reads (`hooks/hooks.json`, `hooks/codex-hooks.json`,
root `hooks.json`), ships the rest of `hooks/<pack>/` except `tests/`, and
copies promoted skills flat into `skills/<name>/`.

## Hooks (`hooks/<pack>/`)

Each hook is one entry script, `hooks/<pack>/<hook>.sh`, whose only argument
names the harness (`claude-code`, `codex`, or `antigravity`). With no
argument it detects Claude Code or Antigravity from the event shape. The
shared code lives in `hooks/<pack>/lib/`:

- `adapter.sh` turns a harness event into a shell command or a list of edited
  paths, and turns the verdict back into that harness's answer.
- `checks.sh` holds the checks.
- `walk.sh` and `shell.awk` split a command line into simple commands. They
  follow `&&`, pipes, subshells, `bash -c`, `eval`, wrappers such as `sudo`
  and `env`, and heredocs fed to a shell.
- `json.awk` parses events without `jq`.

To try a check without a harness:

```bash
bash hooks/engineering/lib/check.sh --hook guard-destructive-git --tool shell --command 'git reset --hard'
```

It exits 0 to allow and 2 to deny, with the reason on stderr.

Rules for hook code:

- Use bash 3.2 and POSIX awk only (macOS ships both). No `jq`, Python, or
  other tools; `cygpath` is used on Windows when present.
- Keep process forks low. Every check runs on every tool call, and process
  start-up is slow on Windows.
- Allow events the adapter cannot parse, with a note on stderr. Ignore a
  malformed `policy.json` with a note, so it grants nothing.
- Read bypasses only from `~/.config/augments-skills/policy.json`. A
  repository's `.augments-skills.json` may only add protected branches.
- On Antigravity, answer `{}` to allow. Never answer `"decision": "allow"`,
  which approves the call outright and skips the harness's own permission
  checks.

`tests/run-engineering-hooks.sh` covers every rule with harness-shaped events
in throwaway repositories and an isolated `HOME`. CI runs it on Linux, on
macOS with `/bin/bash` 3.2, and on Windows. Add a case for every new rule and
for every false positive you fix. Live hook tests inside each harness are
manual for now. User-facing hook behavior is documented in
[`docs/hooks.md`](docs/hooks.md).

When adding or updating a harness adapter, update `scripts/sync-plugins.sh`,
add/update `tests/harnesses/<name>.sh`, run
`tests/run-plugin-smoke.sh --harness <name>`, and update user docs under `docs/`.
The smoke test installs into an isolated home with no model call; with no
promoted skill yet it installs a temporary copy carrying one sample skill.
CI skips it because it needs each harness CLI.

## Opening a pull request

1. Target `dev`.
2. Fill every section of `.github/PULL_REQUEST_TEMPLATE.md` truthfully,
   including orchestrator, model IDs, harness version, and review notes.
3. Wait for all gating CI checks to pass on the current head commit before a
   maintainer merges.
