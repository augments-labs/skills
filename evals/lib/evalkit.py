#!/usr/bin/env python3
"""Deterministic helpers for evals/bin/*: case validation, grading,
benchmark aggregation, the promotion decision table, triggering summaries,
skill frontmatter, and the README scoreboard. Standard library only."""

import fnmatch
import glob
import hashlib
import json
import os
import re
import statistics
import subprocess
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone

KINDS = ("trap", "non_trigger", "small_fix")
ASSERTION_TYPES = ("file-exists", "file-contains", "file-not-contains",
                   "command-succeeds", "git-count", "script")
ARMS = ("full", "distilled", "none", "old_skill")
SPLITS = ("train", "validation", "holdout", "negative")
ID_RE = re.compile(r"^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$")

# Decision table (evals/README.md): distilled ships when it beats none by at
# least this much, passes both control gates, and full adds less than
# FULL_OVER_DISTILLED over it.
DISTILLED_MIN_LIFT = 0.20
FULL_OVER_DISTILLED = 0.10
# Control gates, each measured against the none arm.
NON_TRIGGER_EXTRA_TOOL_CALLS = 1
SMALL_FIX_EXTRA_TOOL_CALLS = 2
SMALL_FIX_EXTRA_TURNS = 1
SMALL_FIX_OUTPUT_TOKEN_RATIO = 1.5

SCOREBOARD_START = "<!-- eval-scoreboard:start -->"
SCOREBOARD_END = "<!-- eval-scoreboard:end -->"
SCOREBOARD_HEADER = [
    "| Skill | Arm shipped | Pass rate (`shipped` vs `none`) | Control delta (non-trigger / small fix) "
    "| Token delta | Model & date | Record |",
    "| --- | --- | --- | --- | --- | --- | --- |",
]
SCOREBOARD_PENDING = ("| *(Pending first evaluated promotion for `v0.0.1`)* "
                      "| n/a | n/a | n/a | n/a | n/a | n/a |")
DASH = "n/a"


class Invalid(Exception):
    pass


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def dump_json(obj, path=None):
    text = json.dumps(obj, indent=2, ensure_ascii=False) + "\n"
    if path is None:
        sys.stdout.write(text)
    else:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def safe_rel(path, what):
    if not isinstance(path, str) or not path:
        raise Invalid(f"{what}: path must be a non-empty string")
    if path.startswith("/") or "\\" in path or any(p == ".." for p in path.split("/")):
        raise Invalid(f"{what}: path must be relative and stay inside its root: {path!r}")
    return path


def contains_key(obj, key):
    if isinstance(obj, dict):
        return key in obj or any(contains_key(v, key) for v in obj.values())
    if isinstance(obj, list):
        return any(contains_key(v, key) for v in obj)
    return False


# ---------------------------------------------------------------- cases ----

def validate_assertion(a, where, case_dir):
    if not isinstance(a, dict):
        raise Invalid(f"{where}: an assertion must be an object")
    t = a.get("type")
    if t not in ASSERTION_TYPES:
        raise Invalid(f"{where}: unknown assertion type {t!r} (allowed: {', '.join(ASSERTION_TYPES)})")
    if t in ("file-exists", "file-contains", "file-not-contains"):
        safe_rel(a.get("path"), where)
    if t in ("file-contains", "file-not-contains"):
        if not isinstance(a.get("pattern"), str) or not a["pattern"]:
            raise Invalid(f"{where}: {t} needs a non-empty regex 'pattern'")
        try:
            re.compile(a["pattern"])
        except re.error as e:
            raise Invalid(f"{where}: invalid regex: {e}")
    if t == "command-succeeds" and (not isinstance(a.get("command"), str) or not a["command"].strip()):
        raise Invalid(f"{where}: command-succeeds needs a 'command'")
    if t == "git-count":
        if a.get("count") not in ("commits", "changed_files"):
            raise Invalid(f"{where}: git-count 'count' must be 'commits' or 'changed_files'")
        if "min" not in a and "max" not in a:
            raise Invalid(f"{where}: git-count needs 'min' and/or 'max'")
        for k in ("min", "max"):
            if k in a and (not isinstance(a[k], int) or isinstance(a[k], bool) or a[k] < 0):
                raise Invalid(f"{where}: git-count '{k}' must be a non-negative integer")
    if t == "script":
        has_src, has_path = isinstance(a.get("source"), str), isinstance(a.get("path"), str)
        if has_src == has_path:
            raise Invalid(f"{where}: script needs exactly one of 'source' (python3 code) or 'path'")
        if has_path:
            safe_rel(a["path"], where)
            if not os.path.isfile(os.path.join(case_dir, a["path"])):
                raise Invalid(f"{where}: verifier not found: {a['path']}")


def load_cases(evals_path, only=None):
    case_dir = os.path.dirname(os.path.abspath(evals_path))
    data = load_json(evals_path)
    if contains_key(data, "pending_first_run"):
        raise Invalid("pending_first_run is not allowed: every case starts with runnable assertions")
    cases = data.get("evals") if isinstance(data, dict) else None
    if not isinstance(cases, list) or not cases:
        raise Invalid("evals.json needs a non-empty 'evals' array")
    seen = set()
    out = []
    for i, c in enumerate(cases):
        where = f"evals[{i}]"
        if not isinstance(c, dict):
            raise Invalid(f"{where}: a case must be an object")
        cid = c.get("id")
        if not isinstance(cid, str) or not ID_RE.match(cid) or "--" in cid:
            raise Invalid(f"{where}: 'id' must be kebab-case")
        if cid in seen:
            raise Invalid(f"{where}: duplicate id {cid!r}")
        seen.add(cid)
        where = f"evals[{cid}]"
        if c.get("kind") not in KINDS:
            raise Invalid(f"{where}: 'kind' must be one of {', '.join(KINDS)}")
        if not isinstance(c.get("prompt"), str) or not c["prompt"].strip():
            raise Invalid(f"{where}: needs a non-empty 'prompt'")
        followups = c.get("followups")
        if "followups" in c:
            if not isinstance(followups, list) or not followups:
                raise Invalid(f"{where}: 'followups' must be a non-empty list of messages")
            for j, m in enumerate(followups):
                if not isinstance(m, str) or not m.strip():
                    raise Invalid(f"{where}.followups[{j}]: a follow-up must be a non-empty string")
        if "fixture" in c:
            safe_rel(c["fixture"], where)
            if not os.path.isdir(os.path.join(case_dir, "files", c["fixture"])):
                raise Invalid(f"{where}: fixture directory not found: files/{c['fixture']}")
        allowed = c.get("allowed_files", [])
        if not isinstance(allowed, list) or not all(isinstance(p, str) for p in allowed):
            raise Invalid(f"{where}: 'allowed_files' must be a list of glob strings")
        if allowed and c["kind"] != "non_trigger":
            raise Invalid(f"{where}: 'allowed_files' applies to non_trigger cases only")
        assertions = c.get("assertions", [])
        if not isinstance(assertions, list):
            raise Invalid(f"{where}: 'assertions' must be a list")
        if c["kind"] != "non_trigger" and not assertions:
            raise Invalid(f"{where}: {c['kind']} cases need at least one assertion")
        for j, a in enumerate(assertions):
            validate_assertion(a, f"{where}.assertions[{j}]", case_dir)
        case = {"id": cid, "kind": c["kind"], "prompt": c["prompt"]}
        if "followups" in c:
            case["followups"] = followups
        case.update({"fixture": c.get("fixture"), "allowed_files": allowed,
                     "assertions": assertions})
        out.append(case)
    if only:
        missing = [x for x in only if x not in seen]
        if missing:
            raise Invalid(f"unknown eval id(s): {', '.join(missing)}")
        out = [c for c in out if c["id"] in only]
    return out


def cmd_cases(args):
    only = None
    if len(args) > 2 and args[1] == "--only":
        only = [x for x in args[2].split(",") if x]
    dump_json(load_cases(args[0], only))


# -------------------------------------------------------------- grading ----

def inside(root, rel):
    full = os.path.realpath(os.path.join(root, rel))
    root = os.path.realpath(root)
    return full if full == root or full.startswith(root + os.sep) else None


def read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return [ln.rstrip("\n") for ln in f if ln.strip()]
    except OSError:
        return None


def run_proc(argv, cwd, env, timeout):
    try:
        p = subprocess.run(argv, cwd=cwd, env=env, timeout=timeout,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return p.returncode, p.stdout.decode("utf-8", "replace")[-400:]
    except subprocess.TimeoutExpired:
        return None, f"timed out after {timeout}s"


_SCRATCH = []


def scratch_home():
    if not _SCRATCH:
        _SCRATCH.append(tempfile.TemporaryDirectory(prefix="eval-verifier-home-"))
    return _SCRATCH[0].name


def grade_assertion(a, workdir, run_dir, case_dir):
    t = a["type"]
    changed_path = os.path.join(run_dir, "changed-files.txt")
    if t in ("file-exists", "file-contains", "file-not-contains"):
        full = inside(workdir, a["path"])
        if full is None:
            return "fail", "path escapes the work tree"
        if not os.path.isfile(full):
            return "fail", f"{a['path']} does not exist"
        if t == "file-exists":
            return "pass", f"{a['path']} exists"
        with open(full, encoding="utf-8", errors="replace") as f:
            text = f.read()
        flags = re.MULTILINE | (re.IGNORECASE if a.get("ignore_case") else 0)
        found = re.search(a["pattern"], text, flags) is not None
        if t == "file-contains":
            return ("pass", "pattern found") if found else ("fail", "pattern not found")
        return ("fail", "pattern found") if found else ("pass", "pattern absent")
    # Verifiers run code the agent may have written, so they get a scrubbed
    # environment and a throwaway HOME, never the operator's.
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": scratch_home(),
           "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "TERM": "dumb", "NO_COLOR": "1",
           "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
           "EVAL_WORKDIR": workdir, "EVAL_CHANGED_FILES": changed_path, "EVAL_SEED": "seed"}
    timeout = a.get("timeout", 120)
    if t == "command-succeeds":
        rc, out = run_proc(["bash", "-c", a["command"]], workdir, env, timeout)
        if rc is None:
            return "needs_review", out
        return ("pass", "exit 0") if rc == 0 else ("fail", f"exit {rc}: {out.strip()}")
    if t == "git-count":
        if a["count"] == "commits":
            rc, out = run_proc(["git", "rev-list", "--count", "seed..HEAD"], workdir, env, 60)
            if rc != 0 or not out.strip().isdigit():
                return "needs_review", f"git rev-list failed: {out.strip()}"
            n = int(out.strip() or 0)
        else:
            lines = read_lines(changed_path)
            if lines is None:
                return "needs_review", "no changed-files list for this run"
            n = len(lines)
        lo, hi = a.get("min"), a.get("max")
        ok = (lo is None or n >= lo) and (hi is None or n <= hi)
        return ("pass" if ok else "fail"), f"{a['count']}={n}"
    if t == "script":
        if "source" in a:
            argv = [sys.executable, "-I", "-c", a["source"], workdir]
        else:
            argv = [sys.executable, "-I", os.path.join(case_dir, a["path"]), workdir]
        rc, out = run_proc(argv, workdir, env, timeout)
        if rc is None:
            return "needs_review", out
        if rc == 0:
            return "pass", "verifier exit 0"
        if rc == 1:
            return "fail", f"verifier exit 1: {out.strip()}"
        return "needs_review", f"verifier crashed (exit {rc}): {out.strip()}"
    return "needs_review", f"unknown assertion type {t}"


def unrequested_files(case, changed):
    if case["kind"] != "non_trigger":
        return []
    pats = case.get("allowed_files") or []
    return [p for p in changed if not any(fnmatch.fnmatchcase(p, g) for g in pats)]


def cmd_grade(args):
    run_dir, case_path, case_dir = args[0], args[1], args[2]
    case = load_json(case_path)
    status = load_json(os.path.join(run_dir, "run_status.json"))
    changed = read_lines(os.path.join(run_dir, "changed-files.txt")) or []
    results = []
    if status.get("outcome") == "indeterminate":
        summary = {"outcome": "indeterminate", "passed": 0, "failed": 0, "needs_review": 0,
                   "total": len(case["assertions"]), "pass_rate": None}
    else:
        for i, a in enumerate(case["assertions"]):
            st, detail = grade_assertion(a, status["workdir"], run_dir, case_dir)
            results.append({"index": i, "type": a["type"], "description": a.get("description", ""),
                            "status": st, "detail": detail})
        c = Counter(r["status"] for r in results)
        total = len(results)
        outcome = "needs_review" if c["needs_review"] else ("fail" if c["fail"] else "pass")
        summary = {"outcome": outcome, "passed": c["pass"], "failed": c["fail"],
                   "needs_review": c["needs_review"], "total": total,
                   "pass_rate": round(c["pass"] / total, 4) if total else None}
    dump_json({"assertion_results": results, "summary": summary,
               "controls": {"unrequested_files": unrequested_files(case, changed)}},
              os.path.join(run_dir, "grading.json"))
    print(summary["outcome"])


# ------------------------------------------------------------ benchmark ----

def median(xs):
    xs = [x for x in xs if isinstance(x, (int, float)) and not isinstance(x, bool)]
    if not xs:
        return None
    m = statistics.median(xs)
    return int(m) if float(m).is_integer() else round(m, 2)


def mean(xs):
    xs = [x for x in xs if isinstance(x, (int, float)) and not isinstance(x, bool)]
    return round(sum(xs) / len(xs), 1) if xs else None


def rate(passed, scored):
    return round(passed / scored, 4) if scored else None


def collect_runs(ws, plan):
    """{arm: {case_id: [run records]}} from runs/<id>/<arm>/run-<k>/."""
    out = {arm: {c["id"]: [] for c in plan["cases"]} for arm in plan["arm_order"]}
    for c in plan["cases"]:
        for arm in plan["arm_order"]:
            for rd in sorted(glob.glob(os.path.join(ws, "runs", c["id"], arm, "run-*"))):
                try:
                    status = load_json(os.path.join(rd, "run_status.json"))
                    grading = load_json(os.path.join(rd, "grading.json"))
                except (OSError, ValueError):
                    status, grading = {"outcome": "indeterminate", "reason": "missing_record"}, None
                try:
                    metrics = load_json(os.path.join(rd, "metrics.json"))
                except (OSError, ValueError):
                    metrics = {}
                outcome = "indeterminate" if grading is None else grading["summary"]["outcome"]
                out[arm][c["id"]].append({
                    "outcome": outcome, "status": status, "metrics": metrics,
                    "unrequested": len((grading or {}).get("controls", {}).get("unrequested_files", [])),
                    "loaded": bool(status.get("skill_chain")),
                })
    return out


def summarize_arm(cases, runs):
    def scored(kind):
        return [r for c in cases if c["kind"] == kind for r in runs[c["id"]]
                if r["outcome"] in ("pass", "fail")]
    all_runs = [r for c in cases for r in runs[c["id"]]]
    all_scored = [r for r in all_runs if r["outcome"] in ("pass", "fail")]
    trap, nt, sf = scored("trap"), scored("non_trigger"), scored("small_fix")
    has_nt = any(c["kind"] == "non_trigger" for c in cases)
    has_sf = any(c["kind"] == "small_fix" for c in cases)
    m = lambda rs, k: [r["metrics"].get(k) for r in rs]
    return {
        "pass_rate": rate(sum(r["outcome"] == "pass" for r in trap), len(trap)),
        "scored_runs": len(trap),
        "indeterminate_count": sum(r["outcome"] == "indeterminate" for r in all_runs),
        "needs_review_count": sum(r["outcome"] == "needs_review" for r in all_runs),
        "mean_output_tokens": mean(m(all_scored, "output_tokens")),
        "mean_time_seconds": mean(m(all_scored, "time_seconds")),
        "control_non_trigger": {
            "skill_loads": sum(r["loaded"] for r in nt) if nt else None,
            "unrequested_files": sum(r["unrequested"] for r in nt) if nt else None,
            "median_tool_calls": median(m(nt, "tool_calls")),
        } if has_nt else {"skill_loads": None, "unrequested_files": None, "median_tool_calls": None},
        "control_small_fix": {
            "pass_rate": rate(sum(r["outcome"] == "pass" for r in sf), len(sf)),
            "median_output_tokens": median(m(sf, "output_tokens")),
            "median_tool_calls": median(m(sf, "tool_calls")),
            "median_turns": median(m(sf, "turns")),
        } if has_sf else {"pass_rate": None, "median_output_tokens": None,
                          "median_tool_calls": None, "median_turns": None},
    }


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


def delta(summary, a, b):
    if a not in summary or b not in summary:
        return None
    x, y = summary[a]["pass_rate"], summary[b]["pass_rate"]
    return None if x is None or y is None else round(x - y, 4)


def decide(plan, summary, deltas):
    notes = []
    if plan.get("shipped_arm_flag"):
        return plan["shipped_arm_flag"], [f"shipped_arm set by flag: {plan['shipped_arm_flag']}"]
    if plan["mode"] == "edit" or "distilled" not in summary:
        return "full", ["full (no distilled arm measured)"]
    dvn, fvd = deltas.get("distilled_vs_none"), deltas.get("full_vs_distilled")
    fails = control_failures(summary["distilled"], summary.get("none"))
    if dvn is None or dvn < DISTILLED_MIN_LIFT:
        notes.append(f"distilled lift over none {dvn} < {DISTILLED_MIN_LIFT}")
    notes += [f"distilled control gate: {w}" for w in fails]
    if fvd is not None and fvd >= FULL_OVER_DISTILLED:
        notes.append(f"full adds {fvd} >= {FULL_OVER_DISTILLED} over distilled")
    if notes:
        return "full", notes
    return "distilled", ["distilled beats none, passes the controls, and full adds < 0.10"]


def cmd_benchmark(args):
    ws = args[0]
    plan = load_json(os.path.join(ws, "plan.json"))
    runs = collect_runs(ws, plan)
    summary = {arm: summarize_arm(plan["cases"], runs[arm]) for arm in plan["arm_order"]}
    deltas = {}
    for key, a, b in (("full_vs_none", "full", "none"), ("distilled_vs_none", "distilled", "none"),
                      ("full_vs_distilled", "full", "distilled"), ("full_vs_old_skill", "full", "old_skill")):
        if a in summary and b in summary:
            deltas[key] = delta(summary, a, b)
    shipped, notes = decide(plan, summary, deltas)
    models = Counter(r["metrics"].get("model") for arm in runs.values() for rs in arm.values()
                     for r in rs if r["metrics"].get("model"))
    model = models.most_common(1)[0][0] if models else (plan.get("model_flag") or "unknown")
    record = {
        "schema_version": 1, "pack": plan["pack"], "skill": plan["skill"], "mode": plan["mode"],
        "shipped_arm": shipped, "measured_at": plan.get("finished_at") or utc_now(),
        "harness": plan["harness"], "harness_version": plan.get("harness_version") or "unknown",
        "model": model, "runs_per_eval": plan["runs_per_eval"], "hooks_enabled": False,
        "arms": {arm: plan["arms"][arm] for arm in plan["arm_order"]},
        "run_summary": summary,
        "evals": [{"id": c["id"], "kind": c["kind"], "arms": {
            arm: {"scored_runs": sum(r["outcome"] in ("pass", "fail") for r in runs[arm][c["id"]]),
                  "passed": sum(r["outcome"] == "pass" for r in runs[arm][c["id"]]),
                  "indeterminate": sum(r["outcome"] == "indeterminate" for r in runs[arm][c["id"]]),
                  "needs_review": sum(r["outcome"] == "needs_review" for r in runs[arm][c["id"]])}
            for arm in plan["arm_order"]}} for c in plan["cases"]],
        "deltas": deltas,
    }
    dump_json(record, os.path.join(ws, "benchmark.json"))
    for n in notes:
        print(f"decision: {n}", file=sys.stderr)
    for arm in plan["arm_order"]:
        s = summary[arm]
        print(f"{arm}: trap pass_rate={s['pass_rate']} scored={s['scored_runs']} "
              f"indeterminate={s['indeterminate_count']} needs_review={s['needs_review_count']}",
              file=sys.stderr)
    print(f"shipped_arm: {shipped}", file=sys.stderr)


# ----------------------------------------------------------- frontmatter ----

def frontmatter(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    if not lines or lines[0] != "---":
        raise Invalid(f"{path}: missing YAML frontmatter")
    try:
        end = lines.index("---", 1)
    except ValueError:
        raise Invalid(f"{path}: unterminated YAML frontmatter")
    return lines, end


def skill_meta(path):
    lines, end = frontmatter(path)
    meta = {"name": None, "description": None, "manual_only": False}
    for ln in lines[1:end]:
        if ln.startswith("name:"):
            meta["name"] = ln[5:].strip().strip('"')
        elif ln.startswith("description:"):
            v = ln[12:].strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            meta["description"] = v
        elif re.match(r"^disable-model-invocation:\s*true\s*$", ln):
            meta["manual_only"] = True
    if not meta["description"]:
        raise Invalid(f"{path}: no description in frontmatter")
    meta["description_sha256"] = hashlib.sha256(meta["description"].encode("utf-8")).hexdigest()
    return meta


def cmd_skill_meta(args):
    dump_json(skill_meta(args[0]))


def check_candidate_text(text):
    text = text.strip()
    if not text:
        return None, "empty"
    if "\n" in text or "\r" in text:
        return None, "must be a single line"
    if len(text) > 1024:
        return None, f"{len(text)} chars (max 1024)"
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in text):
        return None, "control characters"
    for ch in '<>"\\':
        if ch in text:
            return None, f"forbidden character {ch!r}"
    return text, None


def cmd_check_candidate(args):
    with open(args[0], encoding="utf-8", errors="replace") as f:
        text, why = check_candidate_text(f.read())
    if why:
        print(f"rejected: {why}", file=sys.stderr)
        sys.exit(1)
    print(text)


def cmd_set_description(args):
    path, desc_file = args
    with open(desc_file, encoding="utf-8") as f:
        text, why = check_candidate_text(f.read())
    if why:
        raise Invalid(f"description rejected: {why}")
    lines, end = frontmatter(path)
    for i in range(1, end):
        if lines[i].startswith("description:"):
            lines[i] = "description: " + json.dumps(text, ensure_ascii=False)
            break
    else:
        raise Invalid(f"{path}: no description line to replace")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


# ------------------------------------------------------------ triggering ----

def load_queries(path, manual_only, splits=None):
    data = load_json(path)
    qs = data.get("queries") if isinstance(data, dict) else None
    if not isinstance(qs, list) or not qs:
        raise Invalid("queries.json needs a non-empty 'queries' array")
    out = []
    for i, q in enumerate(qs):
        where = f"queries[{i}]"
        if not isinstance(q, dict) or not isinstance(q.get("query"), str) or not q["query"].strip():
            raise Invalid(f"{where}: needs a non-empty 'query'")
        if not isinstance(q.get("should_trigger"), bool):
            raise Invalid(f"{where}: 'should_trigger' must be true or false")
        if q.get("split") not in SPLITS:
            raise Invalid(f"{where}: 'split' must be one of {', '.join(SPLITS)}")
        if q["split"] == "negative" and q["should_trigger"]:
            raise Invalid(f"{where}: negative-split queries must have should_trigger false")
        if manual_only and q["split"] != "negative":
            raise Invalid(f"{where}: a manual-only skill uses split 'negative' only")
        item = {"index": i, "query": q["query"], "should_trigger": q["should_trigger"],
                "split": q["split"]}
        if "fixture" in q:
            safe_rel(q["fixture"], f"{where}.fixture")
            files = os.path.join(os.path.dirname(os.path.abspath(path)), "files")
            if not os.path.isdir(os.path.join(files, q["fixture"])):
                raise Invalid(f"{where}: fixture directory not found: files/{q['fixture']}")
            item["fixture"] = q["fixture"]
        out.append(item)
    if not manual_only:
        present = {q["split"] for q in out}
        for need in ("train", "validation"):
            if need not in present:
                raise Invalid(f"an auto-triggered skill needs '{need}' queries")
    if splits:
        out = [q for q in out if q["split"] in splits]
    return out


def cmd_queries(args):
    manual = args[1] == "1"
    splits = [s for s in args[2].split(",") if s] if len(args) > 2 and args[2] else None
    dump_json(load_queries(args[0], manual, splits))


def cmd_triggering(args):
    ws = args[0]
    plan = load_json(os.path.join(ws, "plan.json"))
    thr = plan["threshold"]
    per_query, splits = [], {}
    models = Counter()
    for q in plan["queries"]:
        valid = triggered = 0
        for rf in sorted(glob.glob(os.path.join(ws, f"q{q['index']}", "run-*", "result.json"))):
            r = load_json(rf)
            if r.get("model"):
                models[r["model"]] += 1
            if r.get("valid"):
                valid += 1
                triggered += 1 if r.get("triggered") else 0
        rt = round(triggered / valid, 4) if valid else None
        if rt is None:
            verdict = "inconclusive"
        elif q["should_trigger"]:
            verdict = "pass" if rt > thr else "fail"
        else:
            verdict = "pass" if rt < thr else "fail"
        per_query.append(dict(q, valid_runs=valid, triggered_runs=triggered, rate=rt, verdict=verdict))
        s = splits.setdefault(q["split"], {"queries": 0, "passed": 0, "failed": 0, "inconclusive": 0})
        s["queries"] += 1
        s[{"pass": "passed", "fail": "failed", "inconclusive": "inconclusive"}[verdict]] += 1
    out_splits = {}
    for name in SPLITS:
        if name in splits:
            s = splits[name]
            out_splits[name] = {"queries": s["queries"], "passed": s["passed"],
                                "pass_rate": rate(s["passed"], s["passed"] + s["failed"]),
                                "inconclusive": s["inconclusive"]}
    record = {
        "schema_version": 1, "pack": plan["pack"], "skill": plan["skill"],
        "manual_only": plan["manual_only"], "harness": plan["harness"],
        "harness_version": plan.get("harness_version") or "unknown",
        "model": models.most_common(1)[0][0] if models else (plan.get("model_flag") or "unknown"),
        "plugin": plan["plugin"], "runs": plan["runs"], "threshold": thr, "splits": out_splits,
    }
    dump_json(record, os.path.join(ws, "triggering.json"))
    dump_json(per_query, os.path.join(ws, "query-results.json"))


# ---------------------------------------------------------------- report ----

def cmd_record_name(args):
    """Validates a record for evals/results/ and prints its directory name."""
    path = args[0]
    base = os.path.basename(path)
    if base not in ("benchmark.json", "triggering.json"):
        raise Invalid("a record is benchmark.json or triggering.json")
    rec = load_json(path)
    if not isinstance(rec, dict):
        raise Invalid("a record must be a JSON object")
    if rec.get("schema_version") != 1:
        raise Invalid("schema_version must be 1")
    for k in ("pack", "skill", "harness"):
        if not isinstance(rec.get(k), str) or not re.match(r"^[a-z0-9][a-z0-9-]*$", rec[k]):
            raise Invalid(f"'{k}' must be kebab-case")
    if base == "benchmark.json":
        if rec.get("hooks_enabled") is not False:
            raise Invalid("hooks_enabled must be false")
        for arm, ident in rec.get("arms", {}).items():
            if arm != "none" and (not ident or not ident.get("skill_tree") or ident["skill_tree"] == "null"):
                raise Invalid(f"arms.{arm}.skill_tree is null: commit the skill and re-run")
        if rec.get("shipped_arm") not in rec.get("arms", {}):
            raise Invalid("shipped_arm was not measured")
        stamp, suffix = rec["measured_at"], ""
    elif base == "triggering.json":
        p = rec.get("plugin") or {}
        if not p.get("skill_tree") or not p.get("description_sha256"):
            raise Invalid("plugin.skill_tree or plugin.description_sha256 is null: commit the skill and re-run")
        if not rec.get("manual_only") and "validation" not in rec.get("splits", {}):
            raise Invalid("an auto-triggered skill's record needs a validation split")
        if rec.get("manual_only") and "negative" not in rec.get("splits", {}):
            raise Invalid("a manual-only skill's record needs a negative split")
        stamp, suffix = rec.get("measured_at") or utc_now(), "-triggering"
    else:
        raise Invalid("a record is benchmark.json or triggering.json")
    date = (args[1] if len(args) > 1 and args[1] else stamp[:10])
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", date):
        raise Invalid(f"bad date {date!r}")
    model = model_slug(rec.get("model"))
    print(f"{date}-{rec['pack']}-{rec['skill']}-{rec['harness']}{'-' + model if model else ''}{suffix}")


def model_slug(model):
    """A record name's model part: the model id lowercased, other characters as single dashes."""
    if not isinstance(model, str):
        return ""
    return re.sub(r"[^a-z0-9]+", "-", model.lower()).strip("-")


def pct(x):
    return DASH if x is None else f"{round(100 * x)}%"


def signed(x):
    if x is None:
        return DASH
    return f"+{x}" if x >= 0 else str(x)


def diff(a, b):
    return None if a is None or b is None else (a - b if isinstance(a - b, int) else round(a - b, 2))


def cell(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def scoreboard_rows(results_dir):
    latest = {}
    for path in sorted(glob.glob(os.path.join(results_dir, "*", "benchmark.json"))):
        try:
            rec = load_json(path)
            key = (rec["pack"], rec["skill"], str(rec.get("model") or ""))
            order = (rec.get("measured_at", ""), os.path.basename(os.path.dirname(path)))
        except (OSError, ValueError, KeyError, TypeError):
            continue
        if key not in latest or order > latest[key][0]:
            latest[key] = (order, path, rec)
    rows = []
    for key in sorted(latest):
        _, path, rec = latest[key]
        summ = rec.get("run_summary", {})
        shipped = rec.get("shipped_arm", "full")
        s, n = summ.get(shipped, {}), summ.get("none")
        if n:
            ctrl = (f"{signed(diff(s['control_non_trigger']['median_tool_calls'], n['control_non_trigger']['median_tool_calls']))} calls / "
                    f"{signed(diff(s['control_small_fix']['median_tool_calls'], n['control_small_fix']['median_tool_calls']))} calls, "
                    f"{signed(diff(s['control_small_fix']['median_turns'], n['control_small_fix']['median_turns']))} turns")
            tokens = signed(diff(s["control_small_fix"]["median_output_tokens"],
                                 n["control_small_fix"]["median_output_tokens"]))
            if tokens != DASH:
                tokens += " output (small fix)"
        else:
            ctrl = tokens = DASH
        dirname = os.path.basename(os.path.dirname(path))
        rel = f"evals/results/{dirname}/benchmark.json"
        rows.append("| " + " | ".join(cell(c) for c in (
            f"`{rec['pack']}/{rec['skill']}`", f"`{shipped}`",
            f"{pct(s.get('pass_rate'))} vs {pct(n.get('pass_rate')) if n else DASH}",
            ctrl, tokens, f"{rec.get('model', 'unknown')}, {str(rec.get('measured_at', ''))[:10]}",
        )) + f" | [{dirname}]({rel}) |")
    return rows


def cmd_scoreboard(args):
    readme, results_dir = args[0], args[1]
    check = "--check" in args[2:]
    with open(readme, encoding="utf-8") as f:
        text = f.read()
    a, b = text.find(SCOREBOARD_START), text.find(SCOREBOARD_END)
    if a < 0 or b < a:
        raise Invalid(f"{readme}: scoreboard markers not found")
    rows = scoreboard_rows(results_dir) or [SCOREBOARD_PENDING]
    block = SCOREBOARD_START + "\n" + "\n".join(SCOREBOARD_HEADER + rows) + "\n"
    new = text[:a] + block + text[b:]
    if check:
        if new != text:
            print(f"scoreboard drift: {readme} does not match evals/results/; run evals/bin/report --scoreboard",
                  file=sys.stderr)
            sys.exit(1)
        print(f"ok: scoreboard matches {len(rows) if rows != [SCOREBOARD_PENDING] else 0} record(s)")
        return
    if new != text:
        with open(readme, "w", encoding="utf-8") as f:
            f.write(new)
        print(f"updated scoreboard in {readme}")
    else:
        print("scoreboard already current")


COMMANDS = {
    "cases": cmd_cases, "grade": cmd_grade, "benchmark": cmd_benchmark,
    "skill-meta": cmd_skill_meta, "check-candidate": cmd_check_candidate,
    "set-description": cmd_set_description, "queries": cmd_queries,
    "triggering": cmd_triggering, "record-name": cmd_record_name, "scoreboard": cmd_scoreboard,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(f"usage: evalkit.py {{{','.join(COMMANDS)}}} ...", file=sys.stderr)
        return 2
    try:
        COMMANDS[argv[1]](argv[2:])
    except Invalid as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, IndexError) as e:
        print(f"error: {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
