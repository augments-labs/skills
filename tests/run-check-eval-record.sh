#!/usr/bin/env bash
# Offline tests for scripts/check-eval-record.sh. Each case builds a throwaway
# git repository with a base commit and a PR head, writes the records the eval
# harness would commit, and runs the gate from this checkout against it, the
# way CI runs the base branch's gate. No harness CLI, no network, no model call.

set -uo pipefail
export LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$repo/scripts/check-eval-record.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Commits get a fixed identity and never read the operator's git config.
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tests GIT_AUTHOR_EMAIL=tests GIT_COMMITTER_NAME=tests GIT_COMMITTER_EMAIL=tests
mkdir -p "$HOME"

pass=0 failed=0
ok() { pass=$((pass + 1)); echo "  ok    $*"; }
bad() { failed=$((failed + 1)); echo "  FAIL  $*"; }

g() { git -C "$work" -c commit.gpgsign=false -c core.autocrlf=false "$@"; }
commit() { g add -A && g commit -q --no-verify --allow-empty -m "$1"; }

# A repository whose base commit holds two promoted skills and an in-progress
# one; the PR head starts there. Later helpers stage the PR's changes.
fresh() {
  work="$tmp/case$((pass + failed))"
  rm -rf "$work"
  mkdir -p "$work"
  git -C "$work" -c init.defaultBranch=main init -q
  printf '# Fixture\n' > "$work/README.md"
  skill engineering/demo-skill "Use when renaming a widget in the demo app."
  skill engineering/old-skill "Use when doing the old thing."
  skill in-progress/new-skill "Use when doing the new thing."
  mkdir -p "$work/evals/engineering/demo-skill"
  printf '{"evals": []}\n' > "$work/evals/engineering/demo-skill/evals.json"
  commit base
  base="$(g rev-parse HEAD)"
  body="$work/.git/pr-body"
  printf 'A change.\n' > "$body"
}

skill() { # path under skills/, description, [extra frontmatter line]
  mkdir -p "$work/skills/$1"
  printf -- '---\nname: %s\ndescription: "%s"\n%s---\n\n# Sample\n\nDo the thing.\n' \
    "${1##*/}" "$2" "${3:+$3
}" > "$work/skills/$1/SKILL.md"
}

edit_skill() { printf '\nOne more line.\n' >> "$work/skills/$1/SKILL.md"; }
tree() { g rev-parse "HEAD:skills/$1"; }
sha() { python3 -I "$repo/evals/lib/evalkit.py" skill-meta "$work/skills/$1/SKILL.md" |
  python3 -I -c 'import json, sys; print(json.load(sys.stdin)["description_sha256"])'; }
name() { printf 'Eval record: evals/results/%s\n' "$1" >> "$body"; }

# bench|trig DIR [option|path=json ...]: writes a record that passes the gate,
# then applies the overrides. Run summaries and deltas are derived from the
# per-case counts unless --raw is given.
rec() {
  local kind="$1" dir="$work/evals/results/$2"; shift 2
  mkdir -p "$dir"
  if [ "$kind" = bench ]; then
    python3 -I "$tmp/mkrec.py" bench "$dir/benchmark.json" "$@"
  else
    python3 -I "$tmp/mkrec.py" trig "$dir/triggering.json" "$@"
  fi
}

# A promotion of skills/<skill> with a passing benchmark.json and triggering.json.
promote() { # skill, [bench overrides ...]
  local sk="$1"; shift
  commit head
  rec bench "b-${sk##*/}" tree="$(tree "$sk")" "$@"
  rec trig "t-${sk##*/}" tree="$(tree "$sk")" sha="$(sha "$sk")"
  commit records
  name "b-${sk##*/}"
  name "t-${sk##*/}"
}

run() { (cd "$work" && bash "$gate" --base "$base" --head HEAD --evals evals --body "$body" "$@" >"$tmp/out" 2>&1); }
expect_ok() { # description, pattern, gate flags...
  local d="$1" pat="$2" rc=0; shift 2
  run "$@" || rc=$?
  if [ "$rc" -ne 0 ]; then bad "$d (exit $rc)"; sed 's/^/        /' "$tmp/out"
  elif grep -qE -- "$pat" "$tmp/out"; then ok "$d"
  else bad "$d (no /$pat/ in output)"; sed 's/^/        /' "$tmp/out"; fi
}
expect_fail() { # description, pattern, gate flags...
  local d="$1" pat="$2" rc=0; shift 2
  run "$@" || rc=$?
  if [ "$rc" -eq 0 ]; then bad "$d (exit 0)"; sed 's/^/        /' "$tmp/out"
  elif [ "$rc" -ne 1 ]; then bad "$d (exit $rc, wanted 1)"; sed 's/^/        /' "$tmp/out"
  elif grep -qE -- "$pat" "$tmp/out"; then ok "$d"
  else bad "$d (no /$pat/ in output)"; sed 's/^/        /' "$tmp/out"; fi
}

cat > "$tmp/mkrec.py" <<'PY'
import json
import sys

kind, out, args = sys.argv[1], sys.argv[2], sys.argv[3:]
opts = {"tree": "1" * 40, "sha": "2" * 64, "arms": "full,distilled,none"}
raw = manual = False
sets = []
for a in args:
    if a == "--raw":
        raw = True
    elif a == "--manual":
        manual = True
    elif a.split("=", 1)[0] in opts:
        k, v = a.split("=", 1)
        opts[k] = v
    else:
        k, v = a.split("=", 1)
        sets.append((k.split("."), v))


def put(obj, path, value):
    for p in path[:-1]:
        obj = obj[int(p)] if isinstance(obj, list) else obj[p]
    key = int(path[-1]) if isinstance(obj, list) else path[-1]
    if value == "DEL":
        del obj[key]
    else:
        obj[key] = json.loads(value)


def rate(passed, scored):
    return round(passed / scored, 4) if scored else None


if kind == "bench":
    arms = opts["arms"].split(",")
    trees = {"full": opts["tree"], "distilled": opts["tree"], "old_skill": "3" * 40}
    trap_passed = {"full": 3, "distilled": 3, "old_skill": 1, "none": 0}
    r = {
        "schema_version": 1, "pack": "engineering", "skill": "demo-skill",
        "mode": "edit" if "old_skill" in arms else "promotion", "shipped_arm": "full",
        "measured_at": "2026-01-02T00:00:00Z", "harness": "fake", "harness_version": "1",
        "model": "fake-model", "runs_per_eval": 3, "hooks_enabled": False,
        "arms": {a: None if a == "none" else {"commit": "4" * 40, "skill_tree": trees[a]} for a in arms},
        "run_summary": {a: {
            "pass_rate": None, "scored_runs": 0, "indeterminate_count": 0, "needs_review_count": 0,
            "mean_output_tokens": 100, "mean_time_seconds": 1.0,
            "control_non_trigger": {"skill_loads": 0, "unrequested_files": 0, "median_tool_calls": 2},
            "control_small_fix": {"pass_rate": 1.0, "median_output_tokens": 100,
                                  "median_tool_calls": 3, "median_turns": 2}} for a in arms},
        "evals": [{"id": i, "kind": k, "arms": {a: {
            "scored_runs": 3, "passed": trap_passed[a] if k == "trap" else 3,
            "indeterminate": 0, "needs_review": 0} for a in arms}}
            for i, k in (("rename", "trap"), ("typo", "non_trigger"), ("greeting", "small_fix"))],
        "deltas": {},
    }
else:
    r = {
        "schema_version": 1, "pack": "engineering", "skill": "demo-skill", "manual_only": manual,
        "harness": "fake", "harness_version": "1", "model": "fake-model",
        "plugin": {"commit": "4" * 40, "skill_tree": opts["tree"], "description_sha256": opts["sha"]},
        "runs": 3, "threshold": 0.5,
        "splits": {"negative": {"queries": 3, "passed": 3, "pass_rate": 1.0, "inconclusive": 0}} if manual else {
            "train": {"queries": 3, "passed": 3, "pass_rate": 1.0, "inconclusive": 0},
            "validation": {"queries": 2, "passed": 2, "pass_rate": 1.0, "inconclusive": 0},
            "holdout": {"queries": 2, "passed": 2, "pass_rate": 1.0, "inconclusive": 0}},
    }

for path, value in sets:
    put(r, path, value)

if kind == "bench" and not raw:
    for a, s in r["run_summary"].items():
        cells = [e["arms"][a] for e in r["evals"] if a in e["arms"]]
        trap = [e["arms"][a] for e in r["evals"] if e["kind"] == "trap" and a in e["arms"]]
        s["scored_runs"] = sum(c["scored_runs"] for c in trap)
        s["pass_rate"] = rate(sum(c["passed"] for c in trap), s["scored_runs"])
        s["indeterminate_count"] = sum(c["indeterminate"] for c in cells)
        s["needs_review_count"] = sum(c["needs_review"] for c in cells)
    summ = r["run_summary"]
    for key, a, b in (("full_vs_none", "full", "none"), ("distilled_vs_none", "distilled", "none"),
                      ("full_vs_distilled", "full", "distilled"), ("full_vs_old_skill", "full", "old_skill")):
        if a in summ and b in summ:
            x, y = summ[a]["pass_rate"], summ[b]["pass_rate"]
            r["deltas"][key] = None if x is None or y is None else round(x - y, 4)

with open(out, "w") as f:
    json.dump(r, f, indent=2)
    f.write("\n")
PY

echo "check-eval-record.sh: guards"

fresh
printf 'More.\n' >> "$work/README.md"
skill in-progress/new-skill "Use when doing the newer thing."
skill deprecated/gone-skill "Use when doing the gone thing."
commit head
expect_ok "no promoted skill touched" "^ok: no promoted skills modified"

fresh
edit_skill engineering/demo-skill
commit head
expect_fail "a promoted skill change needs an Eval record line" "without 'Eval record: evals/results/<dir>'"
expect_ok "--exempt skips the record" "^ok: --exempt \(no-eval label\) applied for: engineering/demo-skill" --exempt

fresh
mkdir -p "$work/skills/engineering/demo-skill/references"
printf '# Notes\n' > "$work/skills/engineering/demo-skill/references/notes.md"
commit head
expect_fail "a references/ change needs a record too" "without 'Eval record:"

fresh
mkdir -p "$work/skills/engineering/demo-skill/scripts"
printf 'echo hi\n' > "$work/skills/engineering/demo-skill/scripts/run.sh"
commit head
expect_fail "a scripts/ change needs a record too" "without 'Eval record:"

fresh
printf 'x\n' > "$work/skills/engineering/demo-skill/NOTES.txt"
commit head
expect_fail "any other file in a promoted skill needs a record too" "without 'Eval record:"

fresh
printf '# Pack\n' > "$work/skills/engineering/README.md"
commit head
expect_ok "a file directly under a pack is not a skill" "^ok: no promoted skills modified"

fresh
edit_skill engineering/demo-skill
printf '{"evals": [1]}\n' > "$work/evals/engineering/demo-skill/evals.json"
commit head
expect_fail "editing the skill's eval cases in the same PR is refused" "without maintainer label 'eval-assertion-reviewed'"
expect_fail "--exempt does not lift the anti-gaming guard" "without maintainer label" --exempt

fresh
edit_skill engineering/demo-skill
mkdir -p "$work/scripts" && printf 'exit 0\n' > "$work/scripts/check-eval-record.sh"
commit head
expect_fail "changing the gate with a skill is self-attestation" "self-attestation forbidden" --allow-assertion-edit --exempt

fresh
edit_skill engineering/demo-skill
mkdir -p "$work/.github/workflows" && printf 'name: x\n' > "$work/.github/workflows/eval-record.yml"
commit head
expect_fail "changing the gate workflow with a skill is self-attestation" "self-attestation forbidden"

fresh
if (cd "$work" && bash "$gate" --base "$base" --head HEAD --evals evals >"$tmp/out" 2>&1); then rc=0; else rc=$?; fi
[ "$rc" -eq 2 ] && grep -q "are required" "$tmp/out" && ok "a missing --body is a usage error" || bad "a missing --body is a usage error (exit $rc)"
if (cd "$work" && bash "$gate" --base nope --head HEAD --evals evals --body "$body" >"$tmp/out" 2>&1); then rc=0; else rc=$?; fi
[ "$rc" -eq 2 ] && ok "an unknown --base is a usage error" || bad "an unknown --base is a usage error (exit $rc)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip  record contents (python3 not found)"
  echo
  echo "run-check-eval-record: $pass passed, $failed failed"
  [ "$failed" -eq 0 ]
  exit
fi

echo "check-eval-record.sh: record paths"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill
printf 'Eval record: evals/results/../results/b-demo-skill\n' >> "$body"
expect_fail "a traversing record path is refused" "path traversal forbidden"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill
printf 'Eval record: evals/engineering/demo-skill\n' >> "$body"
expect_fail "a record outside evals/results/ is refused" "invalid eval record path 'evals/engineering/demo-skill' \(expected evals/results/<dir>\)"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill
name missing-dir
expect_fail "a named record missing at head is refused" "named eval record 'evals/results/missing-dir' at commit '[0-9a-f]{40}' does not contain"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill
mkdir -p "$work/evals/results/broken" && printf '{"schema_version": 1,\n' > "$work/evals/results/broken/benchmark.json"
commit broken
name broken
expect_fail "a named record that is not JSON is refused" "invalid eval record evals/results/broken/benchmark.json: not valid JSON"

echo "check-eval-record.sh: benchmark.json"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill
expect_ok "a skill edit with passing records" "^ok: eval records verified for promoted skill\(s\): engineering/demo-skill"
grep -q "^ok: skills/engineering/demo-skill/ ships tree $(tree engineering/demo-skill), measured by" "$tmp/out" &&
  ok "the shipped tree and records are reported" || bad "the shipped tree and records are reported"

fresh
mkdir -p "$work/skills/engineering"
g mv skills/in-progress/new-skill skills/engineering/new-skill
commit head
rec bench b-new tree="$(tree engineering/new-skill)" skill='"new-skill"'
rec trig t-new tree="$(tree engineering/new-skill)" sha="$(sha engineering/new-skill)" skill='"new-skill"'
commit records
name b-new && name t-new
expect_ok "a promotion from in-progress with passing records" "^ok: eval records verified for promoted skill\(s\): engineering/new-skill"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill shipped_arm='"distilled"'
expect_ok "shipping distilled when it beats none and full adds < 0.10" "^ok: eval records verified"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)"
commit records
printf 'Eval record: evals/results/b/\r\nEval record:  evals/results/t \r\n' >> "$body"
expect_ok "record lines tolerate a trailing slash, spaces, and CRLF" "^ok: eval records verified"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill
name b-demo-skill && name t-demo-skill
expect_ok "names repeated in the body are read once" "^ok: eval records verified"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
commit records
name b
expect_fail "a benchmark alone is not enough" "no named eval record holds a triggering.json"

fresh
edit_skill engineering/demo-skill
commit head
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)"
commit records
name t
expect_fail "a triggering record alone is not enough" "no named eval record holds a benchmark.json"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill tree="$(g rev-parse "$base:skills/engineering/demo-skill")"
expect_fail "a benchmark of another tree fails" "arms.full.skill_tree [0-9a-f]{40} is not the shipped tree"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill shipped_arm='"distilled"' arms.distilled.skill_tree='"5555555555555555555555555555555555555555"'
expect_fail "the shipped arm's tree is the one compared" "arms.distilled.skill_tree 5{40} is not the shipped tree"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill evals.1.arms.none.scored_runs=2 evals.1.arms.none.passed=2
expect_fail "fewer than 3 scored runs in a case fails" "fewer than 3 scored runs per eval case: typo\[none\]=2"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill evals.0.arms.distilled.indeterminate=1
expect_fail "an indeterminate run fails" "1 indeterminate run\(s\) \(needs 0\)"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill evals.2.arms.none.needs_review=2
expect_fail "a needs_review run fails" "2 needs_review run\(s\) \(needs 0\)"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill --raw run_summary.full.needs_review_count=1 deltas='{"full_vs_none": 1.0, "distilled_vs_none": 1.0, "full_vs_distilled": 0.0}' \
  run_summary.full.pass_rate=1.0 run_summary.full.scored_runs=3 run_summary.distilled.pass_rate=1.0 run_summary.distilled.scored_runs=3 \
  run_summary.none.pass_rate=0.0 run_summary.none.scored_runs=3
expect_fail "a needs_review count in the run summary fails" "1 needs_review run\(s\)"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill hooks_enabled=true
expect_fail "a benchmark with hooks enabled is invalid" "invalid eval record .*benchmark.json: hooks_enabled must be false"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill run_summary.full.control_non_trigger.skill_loads=1
expect_fail "loading the skill on a non-trigger case fails the controls" "full control gate: non_trigger skill_loads=1"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill run_summary.full.control_small_fix.median_turns=4
expect_fail "extra small-fix turns over none fail the controls" "full control gate: small_fix median_turns over none\+1"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill run_summary.full.control_small_fix.median_output_tokens=151
expect_fail "small-fix output over 1.5x none fails the controls" "small_fix median_output_tokens over 1.5x none"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill run_summary.full.control_small_fix.median_output_tokens=150 run_summary.full.control_small_fix.median_turns=3 \
  run_summary.full.control_small_fix.median_tool_calls=5 run_summary.full.control_non_trigger.median_tool_calls=3
expect_ok "controls exactly at their limits pass" "^ok: eval records verified"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill run_summary.none.control_small_fix.pass_rate=null
expect_fail "a none arm with no scored small-fix runs fails the controls" "full control gate: no scored small_fix runs"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill arms=full,old_skill
expect_fail "an edit benchmark without a none arm has no control baseline" "full control gate: no none arm to compare controls against"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill arms=full,old_skill,none
expect_ok "an edit benchmark with old_skill and none arms passes" "^ok: eval records verified"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill shipped_arm='"distilled"' evals.0.arms.distilled.passed=0
expect_fail "shipping distilled without its lift over none fails" "ships distilled, but distilled_vs_none 0.0 < 0.2"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill shipped_arm='"distilled"' evals.0.arms.distilled.passed=2
expect_fail "shipping distilled when full adds >= 0.10 fails" "ships distilled, but full adds 0.3333 >= 0.1 over it"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill shipped_arm='"distilled"' run_summary.distilled.control_non_trigger.unrequested_files=1
expect_fail "shipping distilled when distilled fails the controls fails" "distilled control gate: non_trigger unrequested_files=1"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill evals.0.arms.distilled.passed=0
expect_ok "shipping full is consistent with any decision" "^ok: eval records verified"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill shipped_arm='"old_skill"' arms=full,old_skill,none
expect_fail "shipping old_skill is invalid" "shipped_arm must be a measured full or distilled arm"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill --raw run_summary.full.pass_rate=1.0 run_summary.full.scored_runs=3 run_summary.distilled.pass_rate=1.0 \
  run_summary.distilled.scored_runs=3 run_summary.none.pass_rate=0.5 run_summary.none.scored_runs=3 \
  deltas='{"full_vs_none": 0.5, "distilled_vs_none": 0.5, "full_vs_distilled": 0.0}'
expect_fail "a run summary that disagrees with the per-case counts fails" "run_summary.none disagrees with the per-case counts"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill evals.0.kind='"small_fix"'
expect_fail "a benchmark with no trap case fails" "no trap case measures the skill"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill schema_version=2
expect_fail "another schema version is invalid" "schema_version must be 1"

fresh
edit_skill engineering/demo-skill
promote engineering/demo-skill skill='"old-skill"'
expect_fail "a record for a skill the PR does not change is refused" "is for engineering/old-skill, which this PR does not change"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b1 tree="$(tree engineering/demo-skill)" evals.0.arms.full.indeterminate=1
rec bench b2 tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)"
commit records
name b1 && name b2 && name t
expect_ok "one passing benchmark among several is enough" "^ok: skills/engineering/demo-skill/ ships tree .* measured by evals/results/b2/benchmark.json"

echo "check-eval-record.sh: triggering.json"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(printf '%064d' 7)"
commit records
name b && name t
expect_fail "a description hash mismatch fails" "plugin.description_sha256 0{63}7 does not match the description at head \($(sha engineering/demo-skill)\)"

fresh
skill engineering/demo-skill "Use when renaming a gadget in the demo app."
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(g show "$base:skills/engineering/demo-skill/SKILL.md" > "$tmp/old.md" &&
  python3 -I "$repo/evals/lib/evalkit.py" skill-meta "$tmp/old.md" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["description_sha256"])')"
commit records
name b && name t
expect_fail "triggering measured on the old description fails" "plugin.description_sha256 [0-9a-f]{64} does not match"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(g rev-parse "$base:skills/engineering/demo-skill")" sha="$(sha engineering/demo-skill)"
commit records
name b && name t
expect_fail "triggering measured on another tree fails" "plugin.skill_tree [0-9a-f]{40} is not the shipped tree"

fresh
skill engineering/demo-skill "It's the \"demo\" skill: use when renaming a widget." 'license: MIT'
awk '{ printf "%s\r\n", $0 }' "$work/skills/engineering/demo-skill/SKILL.md" > "$tmp/crlf" && cp "$tmp/crlf" "$work/skills/engineering/demo-skill/SKILL.md"
promote engineering/demo-skill
expect_ok "a CRLF SKILL.md with quotes hashes the way the harness does" "^ok: eval records verified"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)" splits.holdout.passed=1 splits.holdout.pass_rate=0.5
commit records
name b && name t
expect_fail "a failed holdout split fails" "holdout split: 1 of 2 queries failed"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)" splits.holdout=DEL
commit records
name b && name t
expect_fail "an auto-triggered skill needs a holdout split" "no holdout split"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)" splits.validation=DEL
commit records
name b && name t
expect_fail "an auto-triggered record without validation is invalid" "needs a validation split"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)" splits.train.passed=2 splits.train.inconclusive=1
commit records
name b && name t
expect_fail "an inconclusive query fails" "train split: 1 inconclusive queries"

fresh
edit_skill engineering/demo-skill
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)" runs=2
commit records
name b && name t
expect_fail "fewer than 3 triggering runs fails" "runs is 2 \(needs >= 3\)"

fresh
skill engineering/demo-skill "Use when renaming a widget in the demo app." 'disable-model-invocation: true'
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)" --manual
commit records
name b && name t
expect_ok "a manual-only skill passes on its negative split" "^ok: eval records verified"

fresh
skill engineering/demo-skill "Use when renaming a widget in the demo app." 'disable-model-invocation: true'
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)" --manual splits.negative.passed=2 splits.negative.pass_rate=0.6667
commit records
name b && name t
expect_fail "a manual-only skill that triggers itself fails" "negative split: 1 of 3 queries failed"

fresh
skill engineering/demo-skill "Use when renaming a widget in the demo app." 'disable-model-invocation: true'
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)" --manual splits.negative=DEL \
  splits.train='{"queries": 1, "passed": 1, "pass_rate": 1.0, "inconclusive": 0}'
commit records
name b && name t
expect_fail "a manual-only record without a negative split is invalid" "a manual-only skill's record needs a negative split"

fresh
skill engineering/demo-skill "Use when renaming a widget in the demo app." 'disable-model-invocation: true'
commit head
rec bench b tree="$(tree engineering/demo-skill)"
rec trig t tree="$(tree engineering/demo-skill)" sha="$(sha engineering/demo-skill)"
commit records
name b && name t
expect_fail "an auto-triggered record for a manual-only skill fails" "manual_only is false, but the skill at head has disable-model-invocation true"

echo "check-eval-record.sh: retired skills"

fresh
mkdir -p "$work/skills/deprecated"
g mv skills/engineering/old-skill skills/deprecated/old-skill
commit head
expect_fail "retiring a skill needs a record" "without 'Eval record:"
grep -q "^  - engineering/old-skill$" "$tmp/out" && ok "the retired skill is listed" || bad "the retired skill is listed"
rec bench b-old skill='"old-skill"'
commit records
name b-old
expect_ok "a retired skill needs one valid record, matched to nothing" "^ok: skills/engineering/old-skill/ is gone at head; evals/results/b-old/benchmark.json records it"

fresh
g rm -q -r skills/engineering/old-skill
commit head
rec bench b-old skill='"old-skill"' hooks_enabled=true
commit records
name b-old
expect_fail "a removed skill's record must still be valid" "hooks_enabled must be false"

fresh
g rm -q -r skills/engineering/old-skill
commit head
rec bench b-demo
commit records
name b-demo
expect_fail "a removed skill's record must be for that skill" "is for engineering/demo-skill, which this PR does not change"

echo "check-eval-record.sh: guards with records"

fresh
edit_skill engineering/demo-skill
printf '{"evals": [1]}\n' > "$work/evals/engineering/demo-skill/evals.json"
promote engineering/demo-skill
expect_ok "--allow-assertion-edit lets the records decide" "^ok: eval records verified" --allow-assertion-edit
expect_fail "without it the anti-gaming guard holds" "without maintainer label 'eval-assertion-reviewed'"

echo
echo "run-check-eval-record: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
