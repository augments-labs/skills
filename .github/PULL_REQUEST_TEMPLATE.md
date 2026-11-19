> **Branch target:** Normal PRs target `dev`. `main` accepts only release PRs (`dev` -> `main`) and urgent `hotfix/*` PRs, which are back-merged to `dev` with a merge commit.

## Summary

- **Problem / motivation:** <!-- Real failure, gap, or goal (not "looks nicer") -->
- **What changed:** <!-- One to three concise sentences -->
- **Alternatives considered:** <!-- What else you considered and why this is better -->
- **Related:** <!-- `#number, #number` or `none` -->

## Pack & Scope

- **Target:** `engineering` | `in-progress` | `deprecated` | `hooks` | `evals` | `harnesses` | `docs` | `infra`
- **One logical change:** yes / no <!-- If the edits look unrelated, say why they belong together -->

## Verification & Evals

<!-- Paste the exact output of the deterministic checks (scripts/validate.sh, token-budget.sh, validate-trigger-collisions.sh, offline tests, evals/bin/check). -->

```text
paste check output here
```

<!-- Required for any PR that adds, promotes, or edits a skill under skills/<pack>/ (not skills/in-progress/ or skills/deprecated/).
     Write one line per committed record under evals/results/, starting at column 0:
     Eval record: evals/results/<date>-<pack>-<skill>-<harness>
     Eval record: evals/results/<date>-<pack>-<skill>-<harness>-triggering
     If the PR is exempt, write `none: <reason>`. Exemptions (typos, moves, or removals) need the maintainer `no-eval` label. -->

- **Live environments tested:** <!-- Harness + version + model + one-line observation, or `offline checks only` -->

## Authoring & Review Disclosure

| Field | Value |
| --- | --- |
| Orchestrated by | human / agent / both |
| Model(s) + part written | <!-- exact model id(s) and what each wrote, or `n/a` --> |
| Harness + version | <!-- CLI/IDE + version, or `n/a` --> |
| Diff reviewed by | <!-- human name (only if they read it), or reviewer model id and whether it is separate from the writer --> |

- [ ] A human read the **complete diff** at head commit: <!-- `<sha>`. Tick only when the named person actually read that commit. -->
- **Review notes (required if human box is unticked):** <!-- Head commit reviewed, what was checked, and each finding with how it was resolved (or `none`). -->

## Checklist

- [ ] Searched open and closed PRs/issues for duplicates.
- [ ] Ran `bash scripts/sync-plugins.sh` if promoted skills or hooks changed (never hand-edited `plugins/`).
- [ ] Shipped files follow `AGENTS.md`: `agentskills.io` compliant, within size/token caps, no shadowed built-in commands, no custom metadata ledgers, no external references or vendor model names.
- [ ] Did not modify `evals/<pack>/<name>/**` (assertions, queries, fixtures, or distilled) in the same PR as a skill edit, unless a maintainer applied the `eval-assertion-reviewed` label.
- [ ] Did not bump manifest versions or add `CHANGELOG.md` version headings (unless this is a release, `hotfix/*`, or `backmerge/*` PR).

<details>
<summary>New harness support (fill only if adding or changing a harness adapter)</summary>

- Adapter files and `tests/harnesses/<name>.sh` added or updated
- `tests/run-plugin-smoke.sh --harness <name>` output
- Live activation proof on a clean session (redacted)

</details>
