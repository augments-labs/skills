#!/usr/bin/env bash
# Offline tests for scripts/check-eval-record.sh. Each case builds a throwaway
# git repository and checks the gate against committed per-skill records in
# evals/results/<pack>/<skill>.json. No harness CLI, no network, no model call.

set -uo pipefail
export LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$repo/scripts/check-eval-record.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tests GIT_AUTHOR_EMAIL=tests GIT_COMMITTER_NAME=tests GIT_COMMITTER_EMAIL=tests
mkdir -p "$HOME"

pass=0 failed=0
ok() { pass=$((pass + 1)); echo "  ok    $*"; }
bad() { failed=$((failed + 1)); echo "  FAIL  $*"; }

g() { git -C "$work" -c commit.gpgsign=false -c core.autocrlf=false "$@"; }
commit() { g add -A && g commit -q --no-verify --allow-empty -m "$1"; }

fresh() {
  work="$tmp/case$((pass + failed))"
  rm -rf "$work"
  mkdir -p "$work"
  git -C "$work" -c init.defaultBranch=main init -q
  printf '# Fixture\n' > "$work/README.md"
  skill engineering/demo-skill "Use when renaming a widget in the demo app."
  skill in-progress/new-skill "Use when doing the new thing."
  commit base
  base="$(g rev-parse HEAD)"
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

write_rec() { # pack/skill, [key=json ...]
  local sk="$1" pack="${1%%/*}" name="${1#*/}"; shift
  mkdir -p "$work/evals/results/$pack"
  python3 -I - "$work/evals/results/$pack/$name.json" "$pack" "$name" "$(tree "$sk")" "$(sha "$sk")" "$@" <<'PY'
import json, sys
out, pack, name, sk_tree, desc_sha, *overrides = sys.argv[1:]
doc = {
    "pack": pack,
    "skill": name,
    "skill_tree": sk_tree,
    "description_sha256": desc_sha,
    "manual_only": False,
    "results": [{
        "model": "fake-model",
        "harness": "fake",
        "date": "2026-01-02",
        "benchmark": {
            "shipped_arm": "full",
            "pass_rate": 1.0,
            "none_pass_rate": 0.5,
            "scored_runs": 9,
            "min_case_runs": 3,
            "indeterminate": 0,
            "needs_review": 0,
            "controls_passed": True,
        },
        "triggering": {
            "passed": 10,
            "queries": 10,
            "runs": 3,
            "inconclusive": 0,
            "all_passed": True,
        },
    }],
}
for ov in overrides:
    path, val = ov.split("=", 1)
    parts = path.split(".")
    obj = doc
    for p in parts[:-1]:
        obj = obj[int(p)] if isinstance(obj, list) else obj[p]
    key = int(parts[-1]) if isinstance(obj, list) else parts[-1]
    if val == "DEL":
        del obj[key]
    else:
        obj[key] = json.loads(val)
with open(out, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
}

run() { (cd "$work" && bash "$gate" --base "$base" --head HEAD --evals evals "$@" >"$tmp/out" 2>&1); }
expect_ok() {
  local d="$1" pat="$2" rc=0; shift 2
  run "$@" || rc=$?
  if [ "$rc" -ne 0 ]; then bad "$d (exit $rc)"; sed 's/^/        /' "$tmp/out"
  elif grep -qE -- "$pat" "$tmp/out"; then ok "$d"
  else bad "$d (no /$pat/ in output)"; sed 's/^/        /' "$tmp/out"; fi
}
expect_fail() {
  local d="$1" pat="$2" rc=0; shift 2
  run "$@" || rc=$?
  if [ "$rc" -eq 0 ]; then bad "$d (exit 0)"; sed 's/^/        /' "$tmp/out"
  elif [ "$rc" -ne 1 ]; then bad "$d (exit $rc, wanted 1)"; sed 's/^/        /' "$tmp/out"
  elif grep -qE -- "$pat" "$tmp/out"; then ok "$d"
  else bad "$d (no /$pat/ in output)"; sed 's/^/        /' "$tmp/out"; fi
}

echo "check-eval-record.sh"

fresh
printf 'More.\n' >> "$work/README.md"
skill in-progress/new-skill "Use when doing the newer thing."
commit head
expect_ok "no promoted skill touched" "^ok: no promoted skills modified"

fresh
edit_skill engineering/demo-skill
commit head
expect_fail "a promoted skill change without a record fails" "evals/results/engineering/demo-skill.json is missing"
expect_ok "--exempt skips the check" "^ok: --exempt \(no-eval label\)" --exempt

fresh
edit_skill engineering/demo-skill
commit head
write_rec engineering/demo-skill
commit rec
expect_ok "a matching passing record passes" "^ok: skills/engineering/demo-skill/ verified by evals/results/engineering/demo-skill.json"

fresh
g mv skills/in-progress/new-skill skills/engineering/new-skill
commit head
write_rec engineering/new-skill
commit rec
expect_ok "a promotion from in-progress passes with its record" "^ok: skills/engineering/new-skill/ verified"

fresh
edit_skill engineering/demo-skill
commit head
write_rec engineering/demo-skill skill_tree='"0000000000000000000000000000000000000000"'
commit rec
expect_fail "a stale skill_tree fails" "skill_tree 0{40} != shipped tree"

fresh
edit_skill engineering/demo-skill
commit head
write_rec engineering/demo-skill description_sha256='"0000000000000000000000000000000000000000000000000000000000000000"'
commit rec
expect_fail "a mismatched description_sha256 fails" "description_sha256 does not match"

fresh
skill engineering/demo-skill "Use when renaming a widget in the demo app." 'disable-model-invocation: true'
commit head
write_rec engineering/demo-skill manual_only=false
commit rec
expect_fail "manual_only mismatch fails" "manual_only does not match"
write_rec engineering/demo-skill manual_only=true
commit rec2
expect_ok "manual-only skill with matching flag passes" "^ok: skills/engineering/demo-skill/ verified"

fresh
edit_skill engineering/demo-skill
commit head
write_rec engineering/demo-skill results.0.benchmark.controls_passed=false
commit rec
expect_fail "failed controls fail the gate" "no passing benchmark entry"

fresh
edit_skill engineering/demo-skill
commit head
write_rec engineering/demo-skill results.0.benchmark.min_case_runs=2
commit rec
expect_fail "fewer than 3 runs per case fails" "no passing benchmark entry"

fresh
edit_skill engineering/demo-skill
commit head
write_rec engineering/demo-skill results.0.benchmark.indeterminate=1
commit rec
expect_fail "indeterminate runs fail" "no passing benchmark entry"

fresh
edit_skill engineering/demo-skill
commit head
write_rec engineering/demo-skill results.0.triggering.all_passed=false
commit rec
expect_fail "failed triggering fails" "no passing triggering entry"

fresh
g rm -q -r skills/engineering/demo-skill
commit head
expect_ok "removing or retiring a skill passes" "^ok: skills/engineering/demo-skill/ removed or retired"

echo
echo "run-check-eval-record: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
