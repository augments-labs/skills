# AGENTS.md

`augments-labs/skills` is a multi-pack monorepo of eval-backed Agent Skills and
deterministic hooks for coding agents, built on the open Agent Skills standard
(`agentskills.io`).

Two core principles:

1. **Mechanical invariants belong in hooks; non-obvious judgment belongs in
   skills.** Never add prompt prose to compensate for a missing deterministic
   check.
2. **Every promoted skill earns its place with measured evals.** A skill stays
   promoted only while `skill` vs `none` evals show a real gain on current
   models without regressing simple control tasks.

## Repository layout

- `skills/<pack>/<name>/`: canonical promoted skills. Edit here; never hand-edit
  `plugins/`.
- `skills/in-progress/<name>/`: optional staging area for unpromoted skills.
  Excluded from plugin bundles.
- `skills/deprecated/<name>/`: optional archive for retired skills.
- `hooks/<pack>/`: pack-scoped deterministic hook logic and harness adapters.
- `plugins/<plugin>/`: generated self-contained per-pack bundles built by
  `bash scripts/sync-plugins.sh` for all 11 supported harnesses (Claude Code,
  Codex CLI, Antigravity, Cursor, Devin, Grok Build, Kimi Code, Muse Code,
  Hermes, OpenCode 2.x, pi) plus `npx skills add`. Never hand-edit `plugins/`.
- `evals/`: eval harness (`evals/bin/`), test cases (`evals/<pack>/<name>/`),
  and one compact committed summary per skill (`evals/results/<pack>/<name>.json`).
  `evals/` never ships inside `plugins/`, and `evals/workspaces/` is gitignored.
- `docs/`: user documentation in plain, natural second-person English (avoid em
  dashes). Maintainer notes go in `CONTRIBUTING.md`.

Edit `AGENTS.md`, never `CLAUDE.md` or `GEMINI.md` (both are symlinks to
`AGENTS.md`).

## Branching and releases

- **`dev` is the integration branch.** Cut a branch from `dev` (for example
  `task/<topic>`), push it, and open a PR into `dev`. Never commit or push
  directly to `dev` or `main`.
- **PRs into `dev` are squash-merged.**
- **`main` receives releases and hotfixes only** (see `RELEASING.md`). Never
  bump versions or add `CHANGELOG.md` version headings in ordinary PRs.

## Authoring rules

Files under `skills/`, `hooks/`, `plugins/`, and `docs/` ship to users.

1. **Agent Skills standard.** Every skill directory contains `SKILL.md` with a
   double-quoted `description` (1 to 1,024 chars) and a kebab-case `name`
   matching its directory. Prefer gerund or activity names (`debugging`,
   `finishing-a-branch`, `reviewing-code`) that avoid built-in slash commands
   (`review`, `simplify`, `plan`, `help`, `clear`, `compact`). User-invoked
   workflows set `disable-model-invocation: true` plus explicit manual-only
   wording in `description`. Never declare inline `hooks` in `SKILL.md`.
2. **Size ceilings.** Every promoted `SKILL.md` body is at most 200 lines,
   2,000 approx tokens, and 8,000 bytes (target 80 to 150 lines). Per pack,
   auto-triggered descriptions stay within 3,400 chars, user-invoked within
   2,400 chars, and combined within 5,800 chars.
3. **Zero library bureaucracy.** No hidden metadata directories, custom ledgers,
   or fill-in-every-section templates. Bind evidence to native artifacts (git
   commits, command output, tests, PR descriptions).
4. **No shouting or silent chaining.** No `<EXTREMELY-IMPORTANT>` banners.
   User-invoked skills may invoke auto-triggered primitives, never another
   user-invoked workflow.
5. **No external references.** Never name other repositories, projects,
   articles, authors, benchmarks, or issue/PR numbers in shipped files, commits,
   PR descriptions, or release notes (outside `README.md` Acknowledgements and
   the PR template `Related` line).
6. **Model- and harness-agnostic.** Inside `skills/`, `hooks/`, `plugins/`, and
   `docs/`, use capability tiers (`small | medium | large`), never vendor model
   names. Keep harness tool names in adapters, not `SKILL.md`. (`evals/results/`
   and the `README.md` scoreboard record tested model IDs.)
7. **No `docs/` links inside skills.** `docs/` does not ship in plugin bundles.
8. **Support-file discipline.** Every line in `SKILL.md` naming a file under
   `references/` or `assets/` must include a load condition (`when`, `if`,
   `before`, `after`). Reference depth is at most 1.
9. **Zero third-party runtime dependencies** in skills, hooks, adapters, and
   scripts.

## Evals and config security

- **Never launch live LLM evals in CI** and never commit `evals/workspaces/`,
  raw transcripts, or secrets. Agents run offline suites (`evals/bin/check`) and
  `--dry-run` unless the user asks for a live run.
- **Hold hooks off during skill evals** so skill deltas are not confounded with
  hooks.
- **Per-skill eval records:** Promoting or editing a skill under
  `skills/<pack>/<name>/` requires an updated, passing record at
  `evals/results/<pack>/<name>.json` (written by `evals/bin/report`, overwritten
  in place so git tracks history). `scripts/check-eval-record.sh` checks that
  `skill_tree`, `description_sha256`, and `manual_only` match `SKILL.md` at head
  and that at least one measured model passes benchmark controls (`>= 3` runs/case,
  0 indeterminate/needs_review) and triggering (`>= 3` runs, 0 inconclusive).
  Typos and removals can use the `no-eval` label.
- **Config trust boundary:** Human hook bypasses and external commands live only
  in `~/.config/augments-skills/`, never in repo-local `.augments-labs-config.json`.
  Hooks must block writes to `~/.config/augments-skills/`.

## Checks before committing

```bash
bash scripts/validate.sh --strict
bash evals/bin/check
```

After editing any promoted skill or hook, run `bash scripts/sync-plugins.sh`.

## Opening and merging PRs

1. Fill `.github/PULL_REQUEST_TEMPLATE.md` truthfully, noting orchestrator,
   model(s), harness, and diff review findings.
2. Only a maintainer (or an explicitly authorized agent) may merge or close a
   PR, and only when gating CI checks are green on head.
