# Releasing

This is the maintainer guide for versioning, cutting releases, and shipping
hotfixes in `augments-labs/skills`. Contributors never bump versions or edit
`CHANGELOG.md` version headings in ordinary contribution PRs.

## Branching contract

- **`main`** holds releases and hotfixes only.
- **`dev`** is the integration branch where all normal PRs land first.
- Every promoted skill changed under `skills/<pack>/` since the previous tag
  must have an up-to-date passing record at `evals/results/<pack>/<skill>.json`
  before a release is cut.

## Versioning

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html):

- **Pre-1.0 (`0.x.y`):** Use `0.0.x` for incremental evaluated additions and
  fixes, and `0.x.0` for milestone batches. Cut `v1.0.0` once the core
  `engineering-skills` pack is stable.
- **Post-1.0 (`1.x.y`+):** Major for breaking surface changes (renamed or
  retired skill, changed install path or hook contract), minor for backwards-compatible
  additions (new skill, pack, hook, or harness), patch for fixes and doc updates.

**Canonical version sources:** `package.json` and `.claude-plugin/marketplace.json`
(`metadata.version` and `plugins[0].version`) hold the canonical version.
Running `bash scripts/sync-plugins.sh` stamps all generated manifests under
`plugins/<plugin>/` and the root `.kimi-plugin/` and `.grok-plugin/` manifests.

## Cutting a release (`dev` -> `main`)

1. Confirm `dev` is green in CI and every promoted skill changed since the last
   tag has an updated record under `evals/results/`.
2. Cut a release branch from `dev` (for example `release/vX.Y.Z`).
3. Bump the version in `package.json` and `.claude-plugin/marketplace.json`,
   run `bash scripts/sync-plugins.sh`, and refresh the `README.md` tables if
   needed (`bash scripts/validate.sh --table` and `evals/bin/report --scoreboard`).
4. Add a concise `## [X.Y.Z] - YYYY-MM-DD` entry to `CHANGELOG.md` stating what
   changed and why users care.
5. Run the full deterministic check suite:
   ```bash
   bash scripts/validate.sh --strict
   bash evals/bin/check
   ```
6. Commit as `chore(release): vX.Y.Z: <short theme>`, merge into `dev` via PR,
   then open and merge the `dev` -> `main` release PR as a **merge commit** so
   `main` never holds a commit `dev` lacks.
7. Tag `vX.Y.Z` on `main` and publish the GitHub Release with concise notes.

## Cutting a hotfix (`hotfix/*` -> `main` -> merge commit to `dev`)

For urgent defects on the latest release (broken hook, corrupt manifest,
security issue):

1. Branch `hotfix/<short-name>` directly from `main`.
2. Apply the minimal fix, bump the patch version in `package.json` and
   `.claude-plugin/marketplace.json`, run `bash scripts/sync-plugins.sh`, add
   the `## [X.Y.Z] - YYYY-MM-DD` entry in `CHANGELOG.md`, and run
   `bash scripts/validate.sh --strict` and `bash evals/bin/check`.
3. Open a PR into `main`, merge once green, tag `vX.Y.(Z+1)`, and publish the
   GitHub Release.
4. Immediately back-merge `main` into `dev` using a merge commit (never squash)
   so git history stays reconciled for the next release.
