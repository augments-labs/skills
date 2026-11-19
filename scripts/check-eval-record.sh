#!/usr/bin/env bash
# Monorepo eval-record, anti-gaming, and self-attestation gate for augments-labs/skills.
#
# A PR that touches any file of a promoted skill, skills/<pack>/<name>/**
# (never skills/in-progress/ or skills/deprecated/), must name committed
# records in its body, one line each, starting at column 0:
#   Eval record: <evals_dir>/results/<dir>
# At --head, every named record must be a valid benchmark.json or
# triggering.json for a touched skill, and every touched skill that still
# exists needs one passing record of each kind:
#   benchmark.json   hooks off; arms.<shipped_arm>.skill_tree is the shipped
#                    tree; >= 3 scored runs per eval case in every measured
#                    arm; no indeterminate or needs_review run; the shipped
#                    arm passes the control gates against a measured none
#                    arm; distilled ships only when the decision table picks it.
#   triggering.json  plugin.skill_tree and plugin.description_sha256 match the
#                    shipped skill; >= 3 runs; the train, validation, and
#                    holdout splits (negative for a manual-only skill) pass
#                    with no failed or inconclusive query.
# A skill removed at head needs one named valid record; nothing is matched.
# Also blocks editing <evals_dir>/<pack>/<name>/** in the same PR without
# --allow-assertion-edit, and self-attestation when this gate itself changes.
#
# CI runs the base branch's copy of this file against the PR head, so it is
# self-contained: it reads records and skills with git at --head and never
# runs code from the tree it judges. The control gates, the decision table,
# and the description hash below mirror evals/lib/evalkit.py; keep them in step.
set -euo pipefail
export LC_ALL=C

base=""
head_rev=""
evals_dir="evals"
body_file=""
exempt=0
allow_assertion_edit=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:-}"; shift $(($# > 1 ? 2 : 1)) ;;
    --head) head_rev="${2:-}"; shift $(($# > 1 ? 2 : 1)) ;;
    --evals) evals_dir="${2:-}"; evals_dir="${evals_dir%/}"; shift $(($# > 1 ? 2 : 1)) ;;
    --body) body_file="${2:-}"; shift $(($# > 1 ? 2 : 1)) ;;
    --exempt) exempt=1; shift ;;
    --allow-assertion-edit) allow_assertion_edit=1; shift ;;
    --help|-h)
      echo "Usage: bash scripts/check-eval-record.sh --base REV --head REV --evals DIR --body FILE [--exempt] [--allow-assertion-edit]"
      exit 0
      ;;
    *)
      echo "check-eval-record.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

[ -n "$base" ] && [ -n "$head_rev" ] && [ -n "$evals_dir" ] && [ -n "$body_file" ] && [ -f "$body_file" ] || {
  echo "check-eval-record.sh: --base, --head, and readable --body are required" >&2
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
# --no-renames lists both sides of a move, so moving a skill out of its pack
# still counts as touching it.
changed=$(git -c core.quotePath=false diff --name-only --no-renames "$mb" "$head_sha")

# Find promoted skills with any changed file. scripts/ counts too: it ships in
# the plugin bundle and the eval bundle, so it changes what was measured.
touched_skills=$(printf '%s\n' "$changed" | awk -F'/' '
  $1 == "skills" && $2 != "in-progress" && $2 != "deprecated" && NF >= 4 {
    print $2 "/" $3
  }
' | sort -u)

if [ -z "$touched_skills" ]; then
  echo "ok: no promoted skills modified; no eval record required."
  exit 0
fi

# Self-attestation guard: a PR changing the eval-record gate cannot attest its own skill change.
if printf '%s\n' "$changed" | grep -qE '^(scripts/check-eval-record\.sh|\.github/workflows/eval-record\.yml)$'; then
  echo "FAIL: PR modifies both promoted skills and the eval-record gate (self-attestation forbidden; split into two PRs)." >&2
  exit 1
fi

# Anti-gaming check: modifying <evals_dir>/<pack>/<name>/** in the same PR as skills/<pack>/<name>/.
if [ "$allow_assertion_edit" -ne 1 ]; then
  while IFS= read -r sk; do
    [ -n "$sk" ] || continue
    if printf '%s\n' "$changed" | grep -qE "^${evals_dir}/${sk}/"; then
      echo "FAIL: PR modifies both skills/${sk}/ and ${evals_dir}/${sk}/ without maintainer label 'eval-assertion-reviewed'." >&2
      exit 1
    fi
  done <<< "$touched_skills"
fi

if [ "$exempt" -eq 1 ]; then
  echo "ok: --exempt (no-eval label) applied for: $(printf '%s' "$touched_skills" | tr '\n' ' ')"
  exit 0
fi

# Every 'Eval record:' line must name one directory directly under <evals_dir>/results/.
errors=0
records=""
named=$(sed -n 's/^Eval record:[[:space:]]*//p' "$body_file" | sed 's/[[:space:]]*$//; s:/$::' | sort -u)
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  case "$rec" in
    *..*|*/.|*/..|.|./*)
      echo "FAIL: invalid eval record path '$rec' (path traversal forbidden)" >&2
      errors=$((errors + 1))
      continue
      ;;
  esac
  dir=""
  case "$rec" in
    "$evals_dir/results/"*) dir="${rec#"$evals_dir/results/"}" ;;
  esac
  case "$dir" in
    ''|*[!A-Za-z0-9._-]*)
      echo "FAIL: invalid eval record path '$rec' (expected ${evals_dir}/results/<dir>)" >&2
      errors=$((errors + 1))
      continue
      ;;
  esac
  records="${records}${rec}
"
done <<< "$named"

if [ -z "$records" ]; then
  [ "$errors" -eq 0 ] || exit 1
  echo "FAIL: promoted skill(s) changed without 'Eval record: ${evals_dir}/results/<dir>' in PR body:" >&2
  while IFS= read -r sk; do
    [ -n "$sk" ] && printf '  - %s\n' "$sk" >&2
  done <<< "$touched_skills"
  exit 1
fi

command -v python3 >/dev/null 2>&1 || {
  echo "check-eval-record.sh: python3 is required to read eval records" >&2
  exit 2
}

# Validate the named records against the touched skills at --head. Isolated
# mode (-I) keeps the interpreter from importing anything from the work tree.
set -- "$head_sha"
while IFS= read -r sk; do
  if [ -n "$sk" ]; then set -- "$@" "$sk"; fi
done <<< "$touched_skills"
set -- "$@" --
while IFS= read -r rec; do
  if [ -n "$rec" ]; then set -- "$@" "$rec"; fi
done <<< "$records"
py_rc=0
python3 -I - "$@" <<'PY' || py_rc=$?
import hashlib
import json
import re
import subprocess
import sys

HEAD = sys.argv[1]
_sep = sys.argv.index("--", 2)
TOUCHED, RECORDS = sys.argv[2:_sep], sys.argv[_sep + 1:]

MIN_RUNS = 3
KEBAB = re.compile(r"[a-z0-9][a-z0-9-]*")
ARMS = ("full", "distilled", "none", "old_skill")
KINDS = ("trap", "non_trigger", "small_fix")
SPLITS = ("train", "validation", "holdout", "negative")
# Copied from evals/lib/evalkit.py on purpose: this gate never runs head's code.
DISTILLED_MIN_LIFT = 0.20
FULL_OVER_DISTILLED = 0.10
NON_TRIGGER_EXTRA_TOOL_CALLS = 1
SMALL_FIX_EXTRA_TOOL_CALLS = 2
SMALL_FIX_EXTRA_TURNS = 1
SMALL_FIX_OUTPUT_TOKEN_RATIO = 1.5
DELTAS = (("full_vs_none", "full", "none"), ("distilled_vs_none", "distilled", "none"),
          ("full_vs_distilled", "full", "distilled"), ("full_vs_old_skill", "full", "old_skill"))
CONTROLS = {"control_non_trigger": ("skill_loads", "unrequested_files", "median_tool_calls"),
            "control_small_fix": ("pass_rate", "median_output_tokens", "median_tool_calls", "median_turns")}
CASE_COUNTS = ("scored_runs", "passed", "indeterminate", "needs_review")


def out(msg):
    print(msg, flush=True)


def err(msg):
    print(msg, file=sys.stderr, flush=True)


def git(*args):
    p = subprocess.run(("git",) + args, stdin=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return p.stdout if p.returncode == 0 else None


def type_at(path):
    t = git("cat-file", "-t", HEAD + ":" + path)
    return None if t is None else t.decode("ascii", "replace").strip()


def tree_at(path):
    t = git("rev-parse", "--verify", "--quiet", HEAD + ":" + path)
    return None if t is None else t.decode("ascii", "replace").strip()


def no_constant(name):
    raise ValueError("non-finite number " + name)


def is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def opt_num(x):
    return x is None or is_num(x)


def count(x):
    return is_int(x) and x >= 0


def same(a, b):
    if a is None or b is None:
        return a is None and b is None
    return abs(a - b) < 1e-9


def rate(passed, scored):
    return round(passed / scored, 4) if scored else None


# ------------------------------------------------- schema (record validity) --

def common_problems(r):
    if not isinstance(r, dict):
        return ["a record must be a JSON object"]
    why = []
    if not is_int(r.get("schema_version")) or r["schema_version"] != 1:
        why.append("schema_version must be 1")
    for k in ("pack", "skill", "harness"):
        if not isinstance(r.get(k), str) or not KEBAB.fullmatch(r[k]):
            why.append(f"'{k}' must be kebab-case")
    return why


def benchmark_problems(r):
    why = common_problems(r)
    if why:
        return why
    if r.get("hooks_enabled") is not False:
        why.append("hooks_enabled must be false")
    arms = r.get("arms")
    if not isinstance(arms, dict) or "full" not in arms or not all(a in ARMS for a in arms):
        return why + ["'arms' must hold the measured arms (full, distilled, none, old_skill), full included"]
    for arm, ident in arms.items():
        if arm != "none" and (not isinstance(ident, dict) or not isinstance(ident.get("skill_tree"), str)
                              or ident["skill_tree"] in ("", "null")):
            why.append(f"arms.{arm}.skill_tree is null")
    if r.get("shipped_arm") not in ("full", "distilled") or r["shipped_arm"] not in arms:
        why.append("shipped_arm must be a measured full or distilled arm")
    summary = r.get("run_summary")
    if not isinstance(summary, dict) or set(summary) != set(arms):
        why.append("run_summary must hold exactly the measured arms")
    else:
        for arm, s in summary.items():
            if not (isinstance(s, dict) and "pass_rate" in s and opt_num(s["pass_rate"])
                    and all(count(s.get(k)) for k in ("scored_runs", "indeterminate_count", "needs_review_count"))
                    and all(isinstance(s.get(g), dict) and all(k in s[g] and opt_num(s[g][k]) for k in keys)
                            for g, keys in CONTROLS.items())):
                why.append(f"run_summary.{arm} is malformed")
    evals = r.get("evals")
    if not isinstance(evals, list) or not evals:
        why.append("'evals' must be a non-empty list")
    else:
        for i, e in enumerate(evals):
            if not (isinstance(e, dict) and isinstance(e.get("id"), str) and e.get("kind") in KINDS
                    and isinstance(e.get("arms"), dict) and set(e["arms"]) == set(arms)
                    and all(isinstance(c, dict) and all(count(c.get(k)) for k in CASE_COUNTS)
                            for c in e["arms"].values())):
                why.append(f"evals[{i}] is malformed")
    deltas = r.get("deltas")
    if not isinstance(deltas, dict) or not all(opt_num(v) for v in deltas.values()):
        why.append("'deltas' must map names to numbers")
    return why


def triggering_problems(r):
    why = common_problems(r)
    if why:
        return why
    manual = r.get("manual_only")
    if not isinstance(manual, bool):
        why.append("manual_only must be true or false")
    p = r.get("plugin")
    if not isinstance(p, dict) or not all(isinstance(p.get(k), str) and p[k] not in ("", "null")
                                          for k in ("skill_tree", "description_sha256")):
        why.append("plugin.skill_tree or plugin.description_sha256 is null")
    if not is_int(r.get("runs")) or r["runs"] < 1:
        why.append("runs must be a positive integer")
    thr = r.get("threshold")
    if not is_num(thr) or not 0 < thr < 1:
        why.append("threshold must be between 0 and 1")
    splits = r.get("splits")
    if not isinstance(splits, dict) or not all(k in SPLITS for k in splits):
        return why + ["'splits' must map train, validation, holdout, or negative to counts"]
    for name, s in splits.items():
        if not (isinstance(s, dict) and all(count(s.get(k)) for k in ("queries", "passed", "inconclusive"))
                and s["passed"] + s["inconclusive"] <= s["queries"] and opt_num(s.get("pass_rate"))):
            why.append(f"splits.{name} is malformed")
    if manual is True and "negative" not in splits:
        why.append("a manual-only skill's record needs a negative split")
    if manual is False and "validation" not in splits:
        why.append("an auto-triggered skill's record needs a validation split")
    return why


# --------------------------------------------------- gate (record passes) --

def control_failures(arm, base):
    """Why `arm` fails the anti-ceremony control gates against `base` (none)."""
    why = []
    if base is None:
        return ["no none arm to compare controls against"]
    nt, bnt = arm["control_non_trigger"], base["control_non_trigger"]
    sf, bsf = arm["control_small_fix"], base["control_small_fix"]
    if nt["skill_loads"] is None:
        why.append("no scored non_trigger runs")
    else:
        if nt["skill_loads"] != 0:
            why.append(f"non_trigger skill_loads={nt['skill_loads']}")
        if nt["unrequested_files"] != 0:
            why.append(f"non_trigger unrequested_files={nt['unrequested_files']}")
        if None in (nt["median_tool_calls"], bnt["median_tool_calls"]) or \
                nt["median_tool_calls"] > bnt["median_tool_calls"] + NON_TRIGGER_EXTRA_TOOL_CALLS:
            why.append("non_trigger median_tool_calls over none+1 (or unknown)")
    if sf["pass_rate"] is None or bsf["pass_rate"] is None:
        why.append("no scored small_fix runs")
    else:
        if sf["pass_rate"] < bsf["pass_rate"]:
            why.append("small_fix pass_rate regressed against none")
        if None in (sf["median_tool_calls"], bsf["median_tool_calls"]) or \
                sf["median_tool_calls"] > bsf["median_tool_calls"] + SMALL_FIX_EXTRA_TOOL_CALLS:
            why.append("small_fix median_tool_calls over none+2 (or unknown)")
        if None in (sf["median_turns"], bsf["median_turns"]) or \
                sf["median_turns"] > bsf["median_turns"] + SMALL_FIX_EXTRA_TURNS:
            why.append("small_fix median_turns over none+1 (or unknown)")
        if None in (sf["median_output_tokens"], bsf["median_output_tokens"]) or \
                sf["median_output_tokens"] > bsf["median_output_tokens"] * SMALL_FIX_OUTPUT_TOKEN_RATIO:
            why.append("small_fix median_output_tokens over 1.5x none (or unknown)")
    return why


def benchmark_failures(r, tree):
    why = []
    arms, shipped, summary, evals = r["arms"], r["shipped_arm"], r["run_summary"], r["evals"]
    got = arms[shipped]["skill_tree"]
    if got != tree:
        why.append(f"arms.{shipped}.skill_tree {got} is not the shipped tree {tree}")
    if not any(e["kind"] == "trap" for e in evals):
        why.append("no trap case measures the skill")
    short = [f"{e['id']}[{a}]={e['arms'][a]['scored_runs']}" for e in evals for a in arms
             if e["arms"][a]["scored_runs"] < MIN_RUNS]
    if short:
        why.append(f"fewer than {MIN_RUNS} scored runs per eval case: " + ", ".join(short))
    for field, total in (("indeterminate", "indeterminate_count"), ("needs_review", "needs_review_count")):
        n = max(sum(e["arms"][a][field] for e in evals for a in arms), sum(summary[a][total] for a in arms))
        if n:
            why.append(f"{n} {field} run(s) (needs 0)")
    for a in arms:
        trap = [e["arms"][a] for e in evals if e["kind"] == "trap"]
        scored = sum(c["scored_runs"] for c in trap)
        if summary[a]["scored_runs"] != scored or \
                not same(summary[a]["pass_rate"], rate(sum(c["passed"] for c in trap), scored)):
            why.append(f"run_summary.{a} disagrees with the per-case counts")
    deltas = {}
    for key, a, b in DELTAS:
        if a in arms and b in arms:
            x, y = summary[a]["pass_rate"], summary[b]["pass_rate"]
            deltas[key] = None if x is None or y is None else round(x - y, 4)
            if not same(r["deltas"].get(key), deltas[key]):
                why.append(f"deltas.{key} disagrees with run_summary")
    why += [f"{shipped} control gate: {w}" for w in control_failures(summary[shipped], summary.get("none"))]
    if shipped == "distilled":
        dvn, fvd = deltas.get("distilled_vs_none"), deltas.get("full_vs_distilled")
        if dvn is None or dvn < DISTILLED_MIN_LIFT:
            why.append(f"ships distilled, but distilled_vs_none {dvn} < {DISTILLED_MIN_LIFT}")
        if fvd is not None and fvd >= FULL_OVER_DISTILLED:
            why.append(f"ships distilled, but full adds {fvd} >= {FULL_OVER_DISTILLED} over it")
    return why


def skill_meta(data):
    """The description hash and manual-only flag, read like evalkit.py skill_meta."""
    try:
        text = data.decode("utf-8")
    except (AttributeError, UnicodeDecodeError):
        return "SKILL.md at head is not readable UTF-8"
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if lines[0] != "---":
        return "SKILL.md at head has no YAML frontmatter"
    try:
        end = lines.index("---", 1)
    except ValueError:
        return "SKILL.md at head has unterminated YAML frontmatter"
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
        return "SKILL.md at head has no description in frontmatter"
    return {"description_sha256": hashlib.sha256(desc.encode("utf-8")).hexdigest(), "manual_only": manual}


def triggering_failures(r, tree, meta):
    why = []
    p, splits = r["plugin"], r["splits"]
    if p["skill_tree"] != tree:
        why.append(f"plugin.skill_tree {p['skill_tree']} is not the shipped tree {tree}")
    if isinstance(meta, str):
        why.append(meta)
        manual = r["manual_only"]
    else:
        manual = meta["manual_only"]
        if p["description_sha256"] != meta["description_sha256"]:
            why.append(f"plugin.description_sha256 {p['description_sha256']} does not match "
                       f"the description at head ({meta['description_sha256']})")
        if r["manual_only"] != manual:
            why.append(f"manual_only is {str(r['manual_only']).lower()}, but the skill at head has "
                       f"disable-model-invocation {str(manual).lower()}")
    if r["runs"] < MIN_RUNS:
        why.append(f"runs is {r['runs']} (needs >= {MIN_RUNS})")
    for name in (("negative",) if manual else ("train", "validation", "holdout")):
        if name not in splits:
            why.append(f"no {name} split")
    for name in SPLITS:
        s = splits.get(name)
        if s is None:
            continue
        failed = s["queries"] - s["passed"] - s["inconclusive"]
        if not s["queries"]:
            why.append(f"{name} split has no queries")
        if failed:
            why.append(f"{name} split: {failed} of {s['queries']} queries failed")
        if s["inconclusive"]:
            why.append(f"{name} split: {s['inconclusive']} inconclusive queries")
    return why


def first_passing(d, kind, recs, gate):
    if not recs:
        err(f"FAIL: {d}/ changed, but no named eval record holds a {kind} for it")
        return None
    report = []
    for path, r in recs:
        why = gate(r)
        if not why:
            return path
        report += [f"  - {path}: {w}" for w in why]
    err(f"FAIL: {d}/ changed, but no named {kind} passes:")
    for line in report:
        err(line)
    return None


def main():
    errors = 0
    found = {sk: {"benchmark.json": [], "triggering.json": []} for sk in TOUCHED}
    for rec in RECORDS:
        present = False
        for kind in ("benchmark.json", "triggering.json"):
            path = rec + "/" + kind
            t = type_at(path)
            if t is None:
                continue
            present = True
            r, why = None, []
            if t != "blob":
                why = ["not a file"]
            else:
                try:
                    r = json.loads(git("cat-file", "blob", HEAD + ":" + path).decode("utf-8"),
                                   parse_constant=no_constant)
                except (AttributeError, ValueError, RecursionError):
                    why = ["not valid JSON"]
            if not why:
                why = (benchmark_problems if kind == "benchmark.json" else triggering_problems)(r)
            if why:
                err(f"FAIL: invalid eval record {path}: " + "; ".join(why))
                errors += 1
                continue
            sk = r["pack"] + "/" + r["skill"]
            if sk not in found:
                err(f"FAIL: eval record {path} is for {sk}, which this PR does not change")
                errors += 1
                continue
            found[sk][kind].append((path, r))
        if not present:
            err(f"FAIL: named eval record '{rec}' at commit '{HEAD}' does not contain benchmark.json or triggering.json")
            errors += 1

    for sk in TOUCHED:
        d = "skills/" + sk
        if type_at(d + "/SKILL.md") != "blob":
            recs = found[sk]["benchmark.json"] + found[sk]["triggering.json"]
            if recs:
                out(f"ok: {d}/ is gone at head; {recs[0][0]} records it (tree and description not matched)")
            else:
                err(f"FAIL: {d}/ is gone at head, but no named eval record is for {sk}")
                errors += 1
            continue
        tree = tree_at(d)
        meta = skill_meta(git("cat-file", "blob", HEAD + ":" + d + "/SKILL.md"))
        bench = first_passing(d, "benchmark.json", found[sk]["benchmark.json"],
                              lambda r: benchmark_failures(r, tree))
        trig = first_passing(d, "triggering.json", found[sk]["triggering.json"],
                             lambda r: triggering_failures(r, tree, meta))
        if bench and trig:
            out(f"ok: {d}/ ships tree {tree}, measured by {bench} and {trig}")
        else:
            errors += 1
    return 1 if errors else 0


try:
    sys.exit(main())
except Exception as e:  # a malformed record must fail the gate, never pass it
    err(f"FAIL: eval record validation stopped: {type(e).__name__}: {e}")
    sys.exit(3)
PY

case "$py_rc" in
  0) ;;
  1) errors=$((errors + 1)) ;;
  *)
    echo "FAIL: eval record validation did not finish (exit $py_rc)" >&2
    errors=$((errors + 1))
    ;;
esac

[ "$errors" -eq 0 ] || exit 1
echo "ok: eval records verified for promoted skill(s): $(printf '%s' "$touched_skills" | tr '\n' ' ')"
