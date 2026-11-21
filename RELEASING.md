# Releasing

This is the maintainer guide for versioning, cutting releases, and shipping
hotfixes in `augments-labs/skills`. Contributors never bump versions or edit
`CHANGELOG.md` version headings in ordinary contribution PRs.

## Branching contract

- **`main`** holds **releases and hotfixes only**.
- **`dev`** is the integration branch where all normal PRs land first.
- Every promoted skill changed under `skills/<pack>/` since the previous tag
  MUST have committed passing eval records under `evals/results/` before a
  release is cut.

## Versioning (starting at `v0.0.1`)

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html):

- **Pre-1.0 (`v0.0.1`, `v0.0.2`, ..., `v0.x.y`):**
  - The repository stays at `0.0.0` (unreleased) until the first evaluated
    promotion.
  - The first public release is **`v0.0.1`**, cut once the first rewritten
    skill and hooks pass evaluation and are promoted into
    `skills/engineering/`.
  - Use `0.0.x` for incremental evaluated additions and fixes, and `0.x.0` for
    milestone batches. Cut **`v1.0.0`** once the core `engineering-skills` pack
    is evaluated and verified across supported harnesses.
- **Post-1.0 (`v1.x.y`+):**
  - **Major:** a breaking change to a pack's public surface (a promoted skill
    is renamed or retired, an install path breaks, or a hook config contract
    breaks). Batch breaking changes into scheduled majors.
  - **Minor:** backwards-compatible growth (a new promoted skill, a new domain
    pack, a new hook, or a new harness adapter).
  - **Patch:** no change to the surface (improved skill text backed by evals,
    hook bug fixes, doc updates, or script/test fixes).

**Canonical version sources:** While `engineering-skills` is the only active
pack, `package.json` and `.claude-plugin/marketplace.json` (`metadata.version`
and `plugins[0].version`) hold the canonical version, and
`bash scripts/sync-plugins.sh` stamps all generated manifests under
`plugins/<plugin>/` automatically (never hand-edit `plugins/`). When a second
domain pack (such as `skills/games/`) ships, each entry in `marketplace.json`
and its `plugins/<plugin>/` bundle are versioned independently
(`<plugin>-vX.Y.Z`), so breaking a pre-1.0 pack never forces a major bump on a
stable pack.

## Cutting a normal release (`dev` -> `main`)

1. Confirm `dev` is green in CI and every promoted skill changed since the last
   tag has committed eval records under `evals/results/`.
2. Decide the next version (`v0.0.1` for the first release, then semver).
3. Cut a release branch from `dev`: `release/vX.Y.Z`.
4. Bump the canonical version in `package.json` and
   `.claude-plugin/marketplace.json`, run `bash scripts/sync-plugins.sh` to
   update all generated pack manifests, and refresh the `README.md` token-budget
   and eval-scoreboard tables.
5. Add a terse `## [X.Y.Z] - YYYY-MM-DD` entry to `CHANGELOG.md`. Use the Keep a
   Changelog heading format with an ASCII hyphen, put the newest entry first,
   and say in one or two sentences what changed and why users care. For a
   major, name each renamed or retired skill.
6. Run the full deterministic check suite:
   ```bash
   bash scripts/validate.sh --strict
   bash scripts/token-budget.sh --check
   bash scripts/validate-trigger-collisions.sh --strict
   bash evals/bin/check
   ```
7. Commit as `chore(release): vX.Y.Z: <one-line theme>`, open a PR into `dev`,
   wait for green CI, and squash-merge into `dev`.
8. Open the `dev` -> `main` release PR titled `Augments Labs Skills vX.Y.Z`, wait
   for green CI (including `release-readiness`), and merge as a **merge commit**
   so `main` never holds a commit `dev` lacks.
9. Create an annotated tag `vX.Y.Z` on `main`, push the tag, and publish the
   GitHub Release with concise notes (what changed, measured eval deltas, and
   any breaking notes).
10. Refresh local plugin caches, for example with
    `claude plugin marketplace update augments-labs` and
    `claude plugin update engineering-skills@augments-labs`.

## Cutting a hotfix (`hotfix/*` -> `main` -> merge commit to `dev`)

Use hotfixes strictly for urgent defects on the latest release (broken hook,
corrupt manifest, security issue):

1. Branch `hotfix/<short-name>` directly from `main`.
2. Apply the minimal fix, bump the patch version in `package.json` and
   `.claude-plugin/marketplace.json`, run `bash scripts/sync-plugins.sh`, add
   the `## [X.Y.Z] - YYYY-MM-DD` entry in `CHANGELOG.md`, and run all
   deterministic checks (plus eval records if a promoted skill's text changed).
3. Open a PR from `hotfix/<short-name>` into `main`, wait for green CI, and
   merge once reviewed.
4. Tag `vX.Y.(Z+1)` on `main` and publish the GitHub Release.
5. **Immediately back-merge `main` into `dev` using a merge commit** (never
   squash-merge, so git history stays reconciled for the next release). If
   `CHANGELOG.md` conflicts, cut a `backmerge/vX.Y.(Z+1)` branch from `dev`,
   merge `main` into it, resolve the conflict there, and merge that branch's PR
   into `dev` as a merge commit.

## Writing `CHANGELOG.md`

Answer two questions in one or two plain sentences per change: **what changed**
and **why a user should care**. Never paste raw diffs, internal reasoning, or
external project/benchmark names. Put narrative evidence and eval tables in the
GitHub Release notes.
