# Evals

The harness measures whether a skill helps an agent. It compares arms (the skill, a distilled skill, no skill) on deterministic cases, and it checks that the skill's description routes the right requests. Every live command is an agent session that costs money. Run `--dry-run` first. CI runs only the offline suites (`evals/bin/check`).

## Layout

```
evals/
  bin/          evaluate · triggering · optimize-description · report · grade · benchmark · check
  lib/          common.sh · home-env.sh · stream-text.sh · evalkit.py (schemas, grading, records)
  lib/tests/    offline suites, fake adapter, tripwire shims, fixtures
  harnesses/    claude-code.sh · codex.sh · antigravity.sh
  <pack>/<skill>/
    evals.json          cases
    files/<fixture>/    fixture trees the cases start from
    queries.json        triggering queries
    distilled/SKILL.md  the distilled arm (optional)
  results/<date>-<pack>-<skill>-<harness>[-triggering]/
    benchmark.json | triggering.json      (committed records, nothing else)
  workspaces/   raw runs (gitignored; never commit)
```

A skill resolves from `skills/<pack>/<name>/` or, if not found there, from `skills/in-progress/<name>/`.

## Commands

```
evals/bin/evaluate --pack PACK --skill NAME [--harness claude-code|codex|antigravity]
    [--arms full,distilled,none | --arms full,old_skill --base COMMIT] [--runs 3]
    [--eval IDS] [--model NAME] [--shipped-arm full|distilled] [--timeout 900]
    [--out DIR] [--keep-workdirs] [--allow-unverified] [--dry-run]

evals/bin/triggering --pack PACK --skill NAME [--harness ...] [--runs 3]
    [--splits train,validation,holdout,negative] [--threshold 0.5] [--jobs 3]
    [--timeout 120] [--max-turns 6] [--description-file F] [--model NAME]
    [--out DIR] [--json] [--allow-unverified] [--dry-run]
    exit: 0 all pass · 1 a query failed or was inconclusive · 2 bad args/unrunnable · 3 CLI missing

evals/bin/optimize-description --pack PACK --skill NAME [--harness ...] [--runs 3]
    [--max-iterations 5] [--apply] [--dry-run] ...

evals/bin/report WORKSPACE|RECORD.json [--date YYYY-MM-DD]
evals/bin/report --scoreboard [--check]
```

`EVALS_COST_PER_SESSION` (a number) prices the plan of a `--dry-run`. `report` copies only the record into `evals/results/`. It refuses to overwrite an existing target, to record a `skill_tree` of `null` (an uncommitted skill or a candidate description), and to record a run with hooks enabled. Recording a benchmark rewrites the README table between `<!-- eval-scoreboard:start -->` and `<!-- eval-scoreboard:end -->`. `--check` exits 1 if that table has drifted from the records.

## Arms

| Arm | Bundle |
|---|---|
| `full` | the working-tree skill dir |
| `distilled` | `evals/<pack>/<skill>/distilled/` |
| `none` | nothing installed |
| `old_skill` | the skill at `--base`, extracted with `git archive` |

A bundle holds `SKILL.md` and the skill's `scripts/`, `references/`, and `assets/` directories, and nothing else. Hooks are off in every arm, and records carry `hooks_enabled: false`. `--arms full,distilled,none` runs in promotion mode. `--arms full,old_skill` runs in edit mode.

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

- **Kinds.** A `trap` case needs at least one assertion. A `non_trigger` case may list `allowed_files` (globs). Any other changed file is counted as `unrequested_files`. A `small_fix` case is a routine task the skill must not slow down.
- **Assertions** are deterministic. Each path must stay inside the work tree, symlinks included. Patterns are Python regexes in multiline mode, and an assertion may set `"ignore_case": true`. A `git-count` counts `commits` or `changed_files` since the seed commit.
- **`script`** gets either python3 `source` or a `path` relative to the case dir. It receives the work dir as `argv[1]`. Exit 0 passes, exit 1 fails, and any other code is `needs_review`. Verifiers and commands run with a scrubbed env (`PATH`, a scratch `HOME`, `EVAL_WORKDIR`, `EVAL_CHANGED_FILES`, `EVAL_SEED=seed`). A timeout is `needs_review`.
- **Indeterminate runs.** A run is indeterminate if it hits any of these: a timeout, a nonzero exit, a refusal or usage limit, no model turn, a skill loaded in `none`, or a setup failure. Indeterminate runs are counted apart and never scored.

## `benchmark.json`

```
{schema_version: 1, pack, skill, mode: "promotion"|"edit", shipped_arm: "full"|"distilled",
 measured_at, harness, harness_version, model, runs_per_eval, hooks_enabled: false,
 arms: {full: {commit, skill_tree}, distilled?: {...}, old_skill?: {...}, none?: null},
 run_summary: {<arm>: {pass_rate, scored_runs, indeterminate_count, needs_review_count,
   mean_output_tokens, mean_time_seconds,
   control_non_trigger: {skill_loads, unrequested_files, median_tool_calls},
   control_small_fix: {pass_rate, median_output_tokens, median_tool_calls, median_turns}}},
 evals: [{id, kind, arms: {<arm>: {scored_runs, passed, indeterminate, needs_review}}}],
 deltas: {full_vs_none?, distilled_vs_none?, full_vs_distilled?, full_vs_old_skill?}}
```

- `pass_rate` covers trap cases only.
- `skill_tree` is `git rev-parse <commit>:<skill dir>`, or `null` when the skill dir has uncommitted changes.
- Deltas are fractions.
- Control metrics are medians, and the token metrics use output tokens.

**Shipped arm.** `--shipped-arm` sets it. Without that flag, the shipped arm is `distilled` when all three of these hold, and `full` otherwise:

- `distilled_vs_none >= 0.20`
- distilled passes the control gates against `none`
- `full_vs_distilled < 0.10`

**Control gates.** The non-trigger gate needs `skill_loads = 0`, `unrequested_files = 0`, and median tool calls of at most none + 1. The small-fix gate needs a pass rate of at least none, median tool calls of at most none + 2, median turns of at most none + 1, and median output tokens of at most 1.5x none.

## Triggering (`queries.json`, `triggering.json`)

```json
{"fixture": "app", "queries": [
  {"query": "Rename the widget called oldWidget", "should_trigger": true, "split": "train"},
  {"query": "What time is it in Tokyo", "should_trigger": false, "split": "validation"}]}
```

```
{schema_version: 1, pack, skill, manual_only, harness, harness_version, model,
 plugin: {commit, skill_tree, description_sha256}, runs, threshold,
 splits: {train: {queries, passed, pass_rate, inconclusive}, validation, holdout?, negative?}}
```

- `description_sha256` is the sha256 of the description value.
- **Scoring.** A should-trigger query passes when its trigger rate is above the threshold. A should-not query passes when its rate is below it. The rate is computed over valid runs. A run is invalid after a refusal, a timeout, a setup failure, or no model turn. A query with no valid run is inconclusive.
- **Manual-only skills** (`disable-model-invocation: true`) take only `split: "negative"` queries, and those queries must not trigger.
- **`optimize-description`** revises the description against train failures only. It picks the iteration with the best validation rate and scores the holdout once, for the winner.

## Isolation

- **Throwaway home.** Each session runs in its own home under `TMPDIR`, with a cleared environment and no session bus. The home is removed after the run.
- **Seeded credentials.** The only things copied in are credential files: `.claude/.credentials.json`, `.codex/auth.json`, and the contents of `$EVALS_CREDENTIAL_SEED/<harness>/`. Seed files get mode 0600. A `.eval-env` file in the seed is sourced by the child process only.
- **Hooks off.** Operator settings, `config.toml`, and hooks are never copied. The claude-code adapter writes `{"disableAllHooks": true}`.
- **Refusal outside isolation.** Adapters refuse to install unless `HOME` is the isolated home.

The following environment variables override paths: `EVALS_REPO_ROOT`, `EVALS_HARNESS_DIR`, `EVALS_WORKSPACE`, `EVALS_CREDENTIAL_SEED`, `EVALS_OPERATOR_HOME`.

## Adapters

An adapter is a sourced shell file. It sets `adapter_name`, `runnable=yes|no`, and `runnable_reason`, and defines these functions: `adapter_check`, `adapter_version`, `adapter_install BUNDLE`, `adapter_run_behavioral WD PROMPT_FILE STREAM`, `adapter_run_activation WD QUERY STREAM`, `adapter_chain`, `adapter_ran`, `adapter_output_tokens`, `adapter_tool_calls`, `adapter_turns`, and `adapter_session_model` (each of the last six takes a STREAM). The runners set the globals `timeout_s`, `errlog`, `maxturns`, and `model`.

| Harness | runnable | Status |
|---|---|---|
| `claude-code` | yes | stream-json parser and install verified against recorded fixtures |
| `codex` | no | parser and install covered offline; not yet validated against a live CLI |
| `antigravity` | no | parser and plugin install covered offline; not yet validated against a live CLI |

`--allow-unverified` runs an adapter marked `runnable=no`. The offline suites use `lib/tests/fake-cli/fake.sh` and a scripted agent. Tripwire shims named `claude`, `codex`, and `agy` sit first on `PATH`, so a suite fails if it ever reaches a real CLI.
