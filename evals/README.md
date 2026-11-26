# Evals

The harness measures whether a skill helps an agent. It compares arms (the skill vs no skill, or an edited skill vs the previous commit) on deterministic cases, and checks that the skill's description routes the right requests. Every live command launches agent sessions that cost money. Run `--dry-run` first. CI runs only the offline suites (`evals/bin/check`).

## Layout

```text
evals/
  bin/          evaluate · triggering · report · grade · benchmark · check
  lib/          common.sh · home-env.sh · stream-text.sh · evalkit.py (schemas, grading, records)
  lib/tests/    offline suites, fake adapter, tripwire shims, fixtures
  harnesses/    claude-code.sh · codex.sh · antigravity.sh
  <pack>/<skill>/
    evals.json          behavior cases and controls
    files/<fixture>/    fixture trees the cases start from
    queries.json        triggering queries
  results/<pack>/<skill>.json
                        compact committed summary per skill (overwritten in place)
  workspaces/   raw runs (gitignored; never commit)
```

A skill resolves from `skills/<pack>/<name>/` or, if not found there, from `skills/in-progress/<name>/`.

## Commands

```text
evals/bin/evaluate --pack PACK --skill NAME [--harness claude-code|codex|antigravity]
    [--arms full,none | --arms full,old_skill,none --base COMMIT
     | --arms [full,]pack[,none]] [--runs 3]
    [--jobs 1] [--eval IDS] [--model NAME]
    [--timeout 900] [--out DIR] [--keep-workdirs] [--allow-unverified] [--dry-run]
evals/bin/evaluate --resume DIR [--jobs 1] [--timeout 900] [--keep-workdirs]
    [--allow-unverified] [--dry-run]

evals/bin/triggering --pack PACK --skill NAME [--harness ...] [--runs 3]
    [--with-skills NAME[,NAME...]|all] [--splits LIST] [--threshold 0.5] [--jobs 3]
    [--timeout 120] [--max-turns 6] [--description-file F] [--model NAME]
    [--out DIR] [--json] [--allow-unverified] [--dry-run]
evals/bin/triggering --pack PACK --skill-dir DIR --queries FILE [options as above]
    exit: 0 all pass · 1 a query failed or was inconclusive · 2 bad args/unrunnable · 3 CLI missing

evals/bin/report WORKSPACE|RECORD.json [--date YYYY-MM-DD]
evals/bin/report --scoreboard [--check]
```

`EVALS_COST_PER_SESSION` (a number) prices the plan of a `--dry-run`. `report` validates a workspace's `benchmark.json` or `triggering.json`, merges its compact summary into `evals/results/<pack>/<skill>.json` (replacing stale entries when `skill_tree` changes, so git tracks history), and refreshes the README scoreboard between `<!-- eval-scoreboard:start -->` and `<!-- eval-scoreboard:end -->`. It refuses a `skill_tree` of `null` (uncommitted skill or candidate description), hooks enabled, composite runs, and `--with-skills` routing runs. `--check` exits 1 if the README table has drifted from `evals/results/`.

## Arms

| Arm | Bundle |
| --- | --- |
| `full` | the working-tree skill dir |
| `none` | nothing installed |
| `old_skill` | the skill at `--base`, extracted with `git archive` |
| `pack` | the skill beside every promoted skill in `skills/<pack>/` |

A bundle holds `SKILL.md` and the skill's `scripts/`, `references/`, and `assets/` directories, and nothing else. Hooks are off in every arm, and records carry `hooks_enabled: false`. `--arms full,none` runs in promotion mode. Including `old_skill` runs in edit mode; keep `none` in it so controls still compare against baseline.

An `--arms` list with `pack` runs in composite mode, an optional check rather than a committed record. Do not re-run it across every unchanged skill before every release. For most neighbor overlap checks, prefer `evals/bin/triggering --with-skills <neighbor>`, which tests 1-turn routing at a fraction of the cost. Use `--arms pack` only when you need to check full multi-turn behavior beside the rest of the pack.

## Cases (`evals.json`)

```json
{"evals": [
  {"id": "rename-widget", "kind": "trap", "fixture": "app",
   "prompt": "Rename the widget oldWidget to newWidget.",
   "assertions": [
     {"type": "file-exists", "path": "src/app.js"},
     {"type": "file-contains", "path": "registry.txt", "pattern": "^newWidget$"},
     {"type": "file-not-contains", "path": "src/app.js", "pattern": "oldWidget"},
     {"type": "command-succeeds", "command": "grep -qx newWidget registry.txt"},
     {"type": "git-count", "count": "changed_files", "min": 1, "max": 2},
     {"type": "script", "path": "verify_registry.py"}]},
  {"id": "fix-readme-typo", "kind": "non_trigger", "fixture": "app",
   "prompt": "Fix the typo in README.md.", "allowed_files": ["README.md"],
   "assertions": [{"type": "git-count", "count": "commits", "max": 0}]},
  {"id": "change-greeting", "kind": "small_fix", "fixture": "app",
   "prompt": "Change the greeting in src/app.js from Hello to Hi.",
   "assertions": [{"type": "script",
     "source": "import sys, pathlib; sys.exit('Hello' in pathlib.Path(sys.argv[1], 'src/app.js').read_text())"}]}
]}
```

- **Kinds.** A `trap` case needs at least one assertion. A `non_trigger` case may list `allowed_files` (globs); any other changed file counts as `unrequested_files`. A `small_fix` case is a routine task the skill must not slow down.
- **Assertions** are deterministic. Paths stay inside the work tree, symlinks included. Patterns are Python regexes in multiline mode, with optional `"ignore_case": true`. `git-count` counts `commits` or `changed_files` since the seed commit.
- **`script`** takes either python3 `source` or a `path` relative to the case dir and receives the work dir as `argv[1]`. Exit 0 passes, exit 1 fails, and any other code or timeout is `needs_review`. Verifiers run with a scrubbed environment and scratch `HOME`.
- **`skill-triggering`** scores a skill the run wrote: `{"type": "skill-triggering", "path": ".agents/skills/*", "queries": "written-queries.json", "runs": 3, "threshold": 0.5}`. After the session, `evaluate` runs `evals/bin/triggering --skill-dir` on the written skill.
- **Follow-ups.** An optional `"followups": [...]` array sends additional messages in order into the same session and grades once on the final work tree. Adapters that do not support follow-ups mark those runs indeterminate (`followups_unsupported`).
- **Indeterminate runs.** Runs hitting a timeout, nonzero exit, provider refusal, no model turn, skill loaded in `none`, setup failure, or unsupported follow-ups are counted apart and never scored.

**Control gates.** The non-trigger gate requires `skill_loads = 0`, `unrequested_files = 0`, and median tool calls at most `none + 1`. The small-fix gate requires pass rate at least `none`, median tool calls at most `none + 2`, median turns at most `none + 1`, and median output tokens at most `1.5x none`.

## Triggering (`queries.json`, `triggering.json`)

```json
{"fixture": "app", "queries": [
  {"query": "Rename the widget called oldWidget", "should_trigger": true},
  {"query": "What time is it in Tokyo", "should_trigger": false},
  {"query": "The billing tests fail since the refactor", "should_trigger": true, "fixture": "billing"}
]}
```

- `split` is optional (defaults to `"all"`, or `"negative"` for manual-only skills). Named splits (`train`, `validation`, `holdout`, `negative`) are still supported with `--splits`.
- A query's `fixture` overrides the file-level one. Seed each query with the files it names so missing files do not overstate trigger rates.
- **Scoring.** A `should_trigger: true` query passes when its trigger rate over valid runs is above `--threshold`; `should_trigger: false` passes when below.
- **Neighbor routing (`--with-skills`).** Pass `--with-skills <neighbor>` (or `--with-skills all`) to install competing skills beside the skill under test. A query fails if any neighbor loads at or above `--threshold`, and the summary prints `other=<skill>:<count>`.
- **Manual-only skills** (`disable-model-invocation: true`) take only `should_trigger: false` queries and confirm the skill never self-fires.

## Isolation and adapters

Each live session runs in a throwaway `HOME` under `TMPDIR` with a cleared environment, no session bus, and hooks disabled. Only explicit credential files (or `$EVALS_CREDENTIAL_SEED/<harness>/`) are copied in with mode `0600`.

| Harness | runnable | Status |
| --- | --- | --- |
| `claude-code` | yes | stream-json parser and install verified; follow-ups use `--continue` |
| `codex` | no | parser and install covered offline; not yet validated against a live CLI |
| `antigravity` | yes | plugin install and stream-json parser verified against live `agy` CLI; follow-ups unsupported |

`--allow-unverified` runs an adapter marked `runnable=no`. Offline tests use `lib/tests/fake-cli/fake.sh` behind tripwire shims so suites fail immediately if any test ever reaches a real CLI.
