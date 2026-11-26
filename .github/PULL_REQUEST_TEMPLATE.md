> **Branch target:** Normal PRs target `dev`. `main` accepts only release (`dev` -> `main`) and `hotfix/*` PRs.

## Summary

- **Motivation:** <!-- Real failure, gap, or goal -->
- **What changed:** <!-- One to three concise sentences -->
- **Related:** <!-- `#number` or `none` -->

## Verification & Evals

```text
paste output of bash scripts/validate.sh --strict and bash evals/bin/check
```

- **Eval record:** <!-- Updated `evals/results/<pack>/<skill>.json` (auto-checked for promoted skill edits), or `n/a` / `no-eval` -->
- **Live environments tested:** <!-- Harness + model + short note, or `offline checks only` -->

## Authoring & Review Disclosure

| Field | Value |
| --- | --- |
| Orchestrated by | human / agent / both |
| Model(s) + part written | <!-- exact model id(s) and what each wrote, or `n/a` --> |
| Harness + version | <!-- CLI/IDE + version, or `n/a` --> |
| Diff reviewed by | <!-- human name (if read at head) or reviewer model id --> |

- [ ] A human read the complete diff at head commit: <!-- `<sha>` -->
- **Review notes:** <!-- Findings and resolutions, or `none` -->

## Checklist

- [ ] Ran `bash scripts/sync-plugins.sh` if promoted skills or hooks changed.
- [ ] Shipped files follow `AGENTS.md` (size caps, no custom ledgers, no external references or vendor model names).
- [ ] Did not bump manifest versions or add `CHANGELOG.md` headings (unless this is a release or hotfix PR).
