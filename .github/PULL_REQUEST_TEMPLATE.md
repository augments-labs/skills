> **Branch target:** Target `dev` for normal PRs. `main` accepts only release PRs (`dev` -> `main`) and urgent `hotfix/*` PRs (which back-merge to `dev` via merge commit).

## Summary

- **Problem / motivation:** <!-- Real failure, gap, or goal (not "looks nicer") -->
- **What changed:** <!-- 1–3 concise sentences -->
- **Alternatives considered:** <!-- What else you considered and why this is better -->
- **Related:** <!-- `#number, #number` or `none` -->

## Pack & Scope

- **Target:** `engineering` | `in-progress` | `deprecated` | `hooks` | `evals` | `harnesses` | `docs` | `infra`
- **One logical change:** yes / no <!-- If coupled edits look separate, name why -->

## Verification & Evals

<!-- Paste exact deterministic check results (scripts/validate.sh, token-budget.sh, validate-trigger-collisions.sh, offline tests, evals/bin/check). -->

```text
paste check output here
```

<!-- Required for any PR adding, promoting, or editing a skill under skills/<pack>/ (excluding skills/in-progress/ and skills/deprecated/).
     One line per committed record under evals/results/, starting at column 0:
     Eval record: evals/results/<date>-<pack>-<skill>-<harness>
     Eval record: evals/results/<date>-<pack>-<skill>-<harness>-triggering
     Write `none: <reason>` if exempt (requires maintainer `no-eval` label for typos, moves, or removals). -->

- **Live environments tested:** <!-- Harness + version + model + one-line observation, or `offline checks only` -->

## Authoring & Review Disclosure

| Field | Value |
| --- | --- |
| Orchestrated by | human / agent / both |
| Model(s) + part written | <!-- exact model id(s) and what each wrote, or `n/a` --> |
| Harness + version | <!-- CLI/IDE + version, or `n/a` --> |
| Diff reviewed by | <!-- human name (only if they read it) or reviewer model id + whether separate from writer --> |

- [ ] A human read the **complete diff** at head commit: <!-- `<sha>` — tick only when the named person actually read that commit -->
- **Review notes (required if human box is unticked):** <!-- Head commit reviewed, what was checked, findings and how each was resolved (or `none`). -->

## Checklist

- [ ] Searched open and closed PRs/issues for duplicates.
- [ ] Ran `bash scripts/sync-plugins.sh` if promoted skills or hooks changed (never hand-edited `plugins/`).
- [ ] Shipped files follow `AGENTS.md`: `agentskills.io` compliant, within size/token caps, no shadowed built-in commands, no custom metadata ledgers, no external references or vendor model names.
- [ ] Did not modify `evals/<pack>/<name>/**` assertions/queries/fixtures/distilled in the same PR as a skill edit (unless maintainer-labelled `eval-assertion-reviewed`).
- [ ] Did not bump manifest versions or add `CHANGELOG.md` version headings (unless this is a release, `hotfix/*`, or `backmerge/*` PR).

<details>
<summary>New harness support (fill only if adding or changing a harness adapter)</summary>

- Adapter files & `tests/harnesses/<name>.sh` added/updated
- `tests/run-plugin-smoke.sh --harness <name>` output
- Live activation proof on a clean session (redacted)

</details>
