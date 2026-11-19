# AGENTS.md

`augments-labs/skills` is a multi-pack monorepo of eval-backed Agent Skills and
deterministic hooks for coding agents, built on the open Agent Skills standard
(`agentskills.io`).

Every rule here rests on two principles:

1. **Mechanical invariants belong in hooks; non-obvious judgment belongs in
   skills.** Never add prompt prose to compensate for a missing deterministic
   check.
2. **A claim about agent behavior leaves through an eval record, never through
   confidence.** A skill stays promoted only while measured 3-arm evals show a
   real gain over no skill on current frontier models without regressing simple
   control tasks.

## Repository layout and naming

Use `<pack>` for source folders (`engineering`, future `games`) and `<plugin>`
for generated plugin bundles (`engineering-skills`, future `roblox-skills`):

- `skills/<pack>/<name>/` — Canonical promoted skills. Edit here; never
  hand-edit generated bundles.
- `skills/in-progress/<name>/` — Staging area for unpromoted skills being
  authored and evaluated. Excluded from all plugin bundles and releases.
- `skills/deprecated/<name>/` — Retired skills that models outgrew, kept with
  the eval record proving zero delta.
- `hooks/<pack>/` — Pack-scoped deterministic hook logic and harness adapters.
  Hooks stay isolated per pack and never leak across packs.
- `plugins/<plugin>/` — Generated, self-contained per-pack bundles built by
  `bash scripts/sync-plugins.sh`. Never edit files under `plugins/` by hand.
- `evals/` — Monorepo 3-arm and triggering eval harness (`evals/bin/`), test
  cases (`evals/<pack>/<name>/`), and compact committed summaries
  (`evals/results/`). `evals/` never ships inside `plugins/<plugin>/`, and
  `evals/workspaces/` is gitignored.
- `docs/` — User documentation in plain second person. Contributor and
  maintainer internals go in `CONTRIBUTING.md`.

Edit `AGENTS.md`, never `CLAUDE.md` or `GEMINI.md` (`GEMINI.md` is a symlink to
`AGENTS.md`).

## Branching and releases

- **`dev` is the integration branch.** Every contribution PR targets `dev` from
  a task branch cut from `dev`.
- **`main` receives releases and hotfixes only.** Normal releases merge
  `dev -> main` as a merge commit. Hotfixes branch `hotfix/<topic>` from `main`,
  merge to `main`, tag a patch version, and immediately back-merge `main -> dev`
  as a merge commit (never squash).
- **Never bump versions or add `CHANGELOG.md` version headings** in an ordinary
  contribution PR. See `RELEASING.md`.

## Authoring rules (non-negotiable)

Files under `skills/`, `hooks/`, `plugins/`, and `docs/` ship to users.

1. **Agent Skills standard first.** Every skill directory contains `SKILL.md`
   with double-quoted `description` (1–1,024 chars), kebab-case `name` matching
   its directory (preferring gerund/activity names such as `debugging`,
   `verifying`, `changing-a-live-schema`, `finishing-a-branch`,
   `reviewing-code` to clearly express the activity and avoid colliding with
   short built-in harness commands like `review`, `simplify`, `plan`, `help`,
   `clear`, `compact`), and optional `scripts/`, `references/`, `assets/`.
   User-invoked workflows carry
   `disable-model-invocation: true` plus explicit manual-only wording in
   `description`. Never declare inline `hooks` in `SKILL.md` frontmatter.
2. **Strict, mathematically consistent size ceilings.** Every promoted
   `SKILL.md` body is at most **200 lines**, **2,000 estimated tokens**, and
   **8,000 bytes** (`ceil(8000 / 4) == 2000`; target 80–150 lines). Per pack,
   auto-triggered descriptions stay within **3,400 characters**, user-invoked
   descriptions within **2,400 characters**, and combined descriptions within
   **5,800 characters**.
3. **Zero library bureaucracy.** Never invent hidden metadata directories,
   append-only custom ledgers, hash-identity formulas, or verbose fill-in-every-
   section templates. Bind evidence to native artifacts (git commits, raw check
   output, tests, PR descriptions).
4. **Zero shouting and zero silent chaining.** No `<EXTREMELY-IMPORTANT>`
   banners and no multi-row rationalization tables unless a 3-arm eval proves
   they improve outcomes. User-invoked skills may invoke auto-triggered
   primitives, never another user-invoked workflow.
5. **No external references.** Never name other repositories, projects,
   articles, authors, benchmarks, or issue/PR numbers in `skills/`, `hooks/`,
   `plugins/`, `docs/`, commit messages, PR descriptions, or release notes
   (outside `README.md`'s Acknowledgements section and the PR template's
   `Related` line). State the engineering principle directly.
6. **Model- and harness-agnostic.** Inside `skills/`, `hooks/`, `plugins/`, and
   `docs/`, name capability tiers (`small | medium | large`), never vendor model
   names (eval records under `evals/results/` and `README.md`'s scoreboard
   record exact tested model IDs). Keep harness tool names inside adapters,
   never inside `SKILL.md`.
7. **No `docs/` links inside skills.** `docs/` does not ship in plugin bundles.
8. **Support-file discipline.** Every line in `SKILL.md` naming a file under
   `references/` or `assets/` must include a load condition (`when`, `if`,
   `before`, `after`). Reference depth is at most 1.
9. **Zero third-party runtime dependencies** in skills, hooks, adapters, and
   core scripts.

## Evals and promotion

- **Never launch live LLM evals in CI** and never commit `evals/workspaces/`,
  raw transcripts, or secrets. Agents may run offline suites (`evals/bin/check`)
  and `--dry-run` only, unless the maintainer explicitly asks for a live run.
- **Hold hooks constant during skill evals.** Skill 3-arm runs (`full`,
  `distilled`, `none`) run with hooks disabled across all arms so skill deltas
  are not confounded with hook enforcement. Hooks have their own deterministic
  and live tests.
- **Staging vs promoted:**
  - Skills in `skills/in-progress/` may be authored and iterated without an eval
    record.
  - Promoting a skill into `skills/<pack>/` or editing any promoted skill's
    `SKILL.md`, `references/`, or `assets/` requires matching committed records
    under `evals/results/` named via `Eval record: evals/results/<dir>` in the
    PR body:
    - **Auto-triggered skill (`description` change or new promotion):**
      `triggering.json` with matching `plugin.description_sha256` (or top-level
      `description_sha256`), `>= 3` runs, a validation split, and zero
      inconclusive queries. Explicit user-invoked skills
      (`disable-model-invocation: true`) are exempt from positive-triggering
      splits, but MUST pass a negative-triggering check on spec-only harnesses
      proving they do not self-fire on routine prompts.
    - **Body/references/assets change or new promotion:** `benchmark.json`
      whose `arms.<shipped_arm>.skill_tree` matches the shipped tree (`full` or
      `distilled` against `none` for promotions; `full` against `old_skill` for
      edits to promoted skills), with `>= 3` scored runs per eval case across
      realistic multi-file tasks plus denominator-safe anti-ceremony controls
      (non-triggering trivial tasks: 0 skill loads, 0 unrequested files,
      `<= +1` tool call; small in-scope fixes: 0 regression, `<= +2` tool
      calls, `<= +1` turn, bounded output tokens), zero indeterminate runs, and
      zero `needs_review` assertions.
  - **Security separation of config:** Human hook bypasses and external CLI
    commands (such as cross-model review commands) live strictly in user-global
    config outside the repository (`~/.config/augments-skills/`), never in
    repo-local `.augments-skills.json`. Hooks MUST also block writes to
    `~/.config/augments-skills/`.
  - **Anti-gaming rule:** Any PR that modifies `evals/<pack>/<name>/**`
    (assertions, queries, fixtures, verifiers, or `distilled/SKILL.md`) in the
    same PR as `skills/<pack>/<name>/` fails CI unless a maintainer applies the
    `eval-assertion-reviewed` label.
  - **Self-attestation rule:** A PR that changes `.github/workflows/eval-record.yml`
    or `scripts/check-eval-record.sh` cannot attest its own skill change; split
    it into two PRs or verify with `dev`'s copy of `scripts/check-eval-record.sh`.
  - **Exemptions:** Typos, removals, or moves between folders require the
    maintainer-applied `no-eval` label. Changes strictly inside `scripts/` or
    outside `skills/` rely on deterministic offline tests.

## Checks before committing

Run before committing; CI enforces these on every push and PR:

```bash
bash scripts/validate.sh --strict
bash scripts/token-budget.sh --check
bash scripts/validate-trigger-collisions.sh --strict
bash evals/bin/check
```

After editing any promoted skill or hook, run `bash scripts/sync-plugins.sh` so
`plugins/<plugin>/` stays synchronized.

## Opening, reviewing, and merging PRs

1. Fill every section of `.github/PULL_REQUEST_TEMPLATE.md` truthfully. Identify
   who orchestrated the change, every model that wrote any part of it, and the
   harness + version.
2. Search open **and** closed PRs and issues before opening a PR.
3. Review the complete diff at the head commit and report findings under
   *Authoring & Review Disclosure*. Tick the human-review box only when the
   named person actually read the diff at that commit.
4. Only a maintainer (or an agent explicitly authorized by a maintainer for that
   PR) may merge or close a PR, and only when every gating CI check is green on
   the current head commit.
