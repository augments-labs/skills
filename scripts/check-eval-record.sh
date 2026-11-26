#!/usr/bin/env bash
# Verifies that any PR adding, promoting, or editing a promoted skill under
# skills/<pack>/<name>/ has a matching, passing record at
# <evals_dir>/results/<pack>/<name>.json at --head.
set -euo pipefail
export LC_ALL=C

base=""
head_rev=""
evals_dir="evals"
exempt=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:-}"; shift $(($# > 1 ? 2 : 1)) ;;
    --head) head_rev="${2:-}"; shift $(($# > 1 ? 2 : 1)) ;;
    --evals) evals_dir="${2:-}"; evals_dir="${evals_dir%/}"; shift $(($# > 1 ? 2 : 1)) ;;
    --exempt) exempt=1; shift ;;
    --help|-h)
      echo "Usage: bash scripts/check-eval-record.sh --base REV --head REV [--evals DIR] [--exempt]"
      exit 0
      ;;
    *)
      echo "check-eval-record.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

[ -n "$base" ] && [ -n "$head_rev" ] && [ -n "$evals_dir" ] || {
  echo "check-eval-record.sh: --base and --head are required" >&2
  exit 2
}

base_sha=$(git rev-parse --verify --quiet "${base}^{commit}") || {
  echo "check-eval-record.sh: --base '$base' is not a commit" >&2
  exit 2
}
head_sha=$(git rev-parse --verify --quiet "${head_rev}^{commit}") || {
  echo "check-eval-record.sh: --head '$head_rev' is not a commit" >&2
  exit 2
}
mb=$(git merge-base "$base_sha" "$head_sha") || {
  echo "check-eval-record.sh: --base and --head share no history" >&2
  exit 2
}

changed=$(git -c core.quotePath=false diff --name-only --no-renames "$mb" "$head_sha")
touched_skills=$(printf '%s\n' "$changed" | awk -F'/' '
  $1 == "skills" && $2 != "in-progress" && $2 != "deprecated" && NF >= 4 {
    print $2 "/" $3
  }
' | sort -u)

if [ -z "$touched_skills" ]; then
  echo "ok: no promoted skills modified; no eval record required."
  exit 0
fi

if [ "$exempt" -eq 1 ]; then
  echo "ok: --exempt (no-eval label) applied for: $(printf '%s' "$touched_skills" | tr '\n' ' ')"
  exit 0
fi

command -v python3 >/dev/null 2>&1 || {
  echo "check-eval-record.sh: python3 is required to read eval records" >&2
  exit 2
}

set -- "$head_sha" "$evals_dir"
while IFS= read -r sk; do
  [ -n "$sk" ] && set -- "$@" "$sk"
done <<< "$touched_skills"

python3 -I - "$@" <<'PY'
import hashlib
import json
import re
import subprocess
import sys

HEAD, EVALS_DIR, TOUCHED = sys.argv[1], sys.argv[2], sys.argv[3:]
MIN_RUNS = 3


def git(*args):
    p = subprocess.run(("git",) + args, stdin=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return p.stdout if p.returncode == 0 else None


def blob_at(path):
    return git("cat-file", "blob", f"{HEAD}:{path}")


def tree_at(path):
    raw = git("rev-parse", "--verify", "--quiet", f"{HEAD}:{path}")
    return None if raw is None else raw.decode("ascii", "replace").strip()


def skill_meta(data):
    lines = data.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if not lines or lines[0] != "---":
        return None, "missing YAML frontmatter"
    try:
        end = lines.index("---", 1)
    except ValueError:
        return None, "unterminated YAML frontmatter"
    desc, manual = None, False
    for ln in lines[1:end]:
        if ln.startswith("description:"):
            v = ln[12:].strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            desc = v
        elif re.match(r"^disable-model-invocation:\s*true\s*$", ln):
            manual = True
    if not desc:
        return None, "missing description in frontmatter"
    return {
        "description_sha256": hashlib.sha256(desc.encode("utf-8")).hexdigest(),
        "manual_only": manual,
    }, None


def bench_ok(b):
    return (
        isinstance(b, dict)
        and b.get("controls_passed") is True
        and isinstance(b.get("min_case_runs"), int) and b["min_case_runs"] >= MIN_RUNS
        and b.get("indeterminate") == 0
        and b.get("needs_review") == 0
        and isinstance(b.get("pass_rate"), (int, float))
    )


def trig_ok(t):
    return (
        isinstance(t, dict)
        and t.get("all_passed") is True
        and isinstance(t.get("runs"), int) and t["runs"] >= MIN_RUNS
        and t.get("inconclusive") == 0
    )


errors = 0
for sk in TOUCHED:
    pack, skill = sk.split("/", 1)
    skill_path = f"skills/{sk}"
    raw_skill = blob_at(f"{skill_path}/SKILL.md")
    if raw_skill is None:
        print(f"ok: {skill_path}/ removed or retired at head.")
        continue

    rec_path = f"{EVALS_DIR}/results/{pack}/{skill}.json"
    raw_rec = blob_at(rec_path)
    if raw_rec is None:
        print(f"FAIL: {skill_path}/ changed, but {rec_path} is missing at head", file=sys.stderr)
        errors += 1
        continue

    try:
        doc = json.loads(raw_rec.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        print(f"FAIL: {rec_path} is not valid JSON", file=sys.stderr)
        errors += 1
        continue

    why = []
    if not isinstance(doc, dict):
        why.append("record must be a JSON object")
    else:
        tree = tree_at(skill_path)
        meta, merr = skill_meta(raw_skill)
        if doc.get("pack") != pack or doc.get("skill") != skill:
            why.append(f"pack/skill does not match {sk}")
        if doc.get("skill_tree") != tree:
            why.append(f"skill_tree {doc.get('skill_tree')} != shipped tree {tree}")
        if merr:
            why.append(merr)
        else:
            if doc.get("description_sha256") != meta["description_sha256"]:
                why.append("description_sha256 does not match SKILL.md at head")
            if doc.get("manual_only") is not meta["manual_only"]:
                why.append("manual_only does not match disable-model-invocation in SKILL.md")
        results = doc.get("results")
        if not isinstance(results, list) or not results:
            why.append("results must be a non-empty list")
        else:
            if not any(bench_ok(e.get("benchmark")) for e in results if isinstance(e, dict)):
                why.append(f"no passing benchmark entry (controls_passed, >= {MIN_RUNS} runs/case, 0 indeterminate/needs_review)")
            if not any(trig_ok(e.get("triggering")) for e in results if isinstance(e, dict)):
                why.append(f"no passing triggering entry (all_passed, >= {MIN_RUNS} runs, 0 inconclusive)")

    if why:
        print(f"FAIL: {rec_path}: " + "; ".join(why), file=sys.stderr)
        errors += 1
    else:
        print(f"ok: {skill_path}/ verified by {rec_path}")

sys.exit(1 if errors else 0)
PY
