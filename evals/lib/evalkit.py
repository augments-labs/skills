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
                   "command-succeeds", "git-count", "script", "skill-triggering")
ARMS = ("full", "none", "old_skill", "pack")
SPLITS = ("all", "train", "validation", "holdout", "negative")
ID_RE = re.compile(r"^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$")
SKILL_NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
# skill-triggering defaults: runs per query and the trigger-rate threshold.
WRITTEN_SKILL_RUNS = 3
WRITTEN_SKILL_THRESHOLD = 0.5

# Control gates, each measured against the none arm.
NON_TRIGGER_EXTRA_TOOL_CALLS = 1
SMALL_FIX_EXTRA_TOOL_CALLS = 2
SMALL_FIX_EXTRA_TURNS = 1
SMALL_FIX_OUTPUT_TOKEN_RATIO = 1.5

SCOREBOARD_START = "<!-- eval-scoreboard:start -->"
SCOREBOARD_END = "<!-- eval-scoreboard:end -->"
SCOREBOARD_HEADER = [
    "| Skill | Pass rate (`skill` vs `none`) | Controls | Triggering | Updated | Record |",
    "| --- | --- | --- | --- | --- | --- |",
]
SCOREBOARD_PENDING = "| *(No evaluated skills yet)* | n/a | n/a | n/a | n/a | n/a |"
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
    if t == "skill-triggering":
        safe_rel(a.get("path"), where)
        safe_rel(a.get("queries"), where)
        qpath = os.path.join(case_dir, a["queries"])
        if not os.path.isfile(qpath):
            raise Invalid(f"{where}: queries file not found: {a['queries']}")
        try:
            load_queries(qpath, False)
        except Invalid as e:
            raise Invalid(f"{where}: {a['queries']}: {e}")
        if "runs" in a and (not isinstance(a["runs"], int) or isinstance(a["runs"], bool) or a["runs"] < 1):
            raise Invalid(f"{where}: skill-triggering 'runs' must be a positive integer")
        thr = a.get("threshold", WRITTEN_SKILL_THRESHOLD)
        if isinstance(thr, bool) or not isinstance(thr, (int, float)) or not 0 < thr < 1:
            raise Invalid(f"{where}: skill-triggering 'threshold' must be between 0 and 1")


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


def grade_written_skill(tdir):
    """Grades a skill-triggering assertion from what evals/bin/evaluate saved
    in <run>/triggering-<i>/: the written skill's triggering on its queries."""
    for name, status in (("invalid.txt", "fail"), ("error.txt", "needs_review")):
        p = os.path.join(tdir, name)
        if os.path.isfile(p):
            with open(p, encoding="utf-8", errors="replace") as f:
                return status, f.read().strip()[:400]
    qr = os.path.join(tdir, "query-results.json")
    if not os.path.isfile(qr):
        return "needs_review", "the written skill's triggering was not run"
    rows = load_json(qr)
    detail = ", ".join(
        f"{label} {sum(r['verdict'] == 'pass' for r in rows if r['should_trigger'] == want)}"
        f"/{sum(r['should_trigger'] == want for r in rows)}"
        for label, want in (("should-trigger", True), ("should-not", False)))
    verdicts = Counter(r["verdict"] for r in rows)
    if verdicts["inconclusive"]:
        return "needs_review", f"{detail}, {verdicts['inconclusive']} inconclusive"
    return ("fail" if verdicts["fail"] else "pass"), detail


def grade_assertion(a, workdir, run_dir, case_dir, index=0):
    t = a["type"]
    if t == "skill-triggering":
        return grade_written_skill(os.path.join(run_dir, f"triggering-{index}"))
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
            st, detail = grade_assertion(a, status["workdir"], run_dir, case_dir, i)
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
                    "chain": [s for s in status.get("skill_chain") or [] if isinstance(s, str)],
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


def cmd_benchmark(args):
    ws = args[0]
    plan = load_json(os.path.join(ws, "plan.json"))
    runs = collect_runs(ws, plan)
    summary = {arm: summarize_arm(plan["cases"], runs[arm]) for arm in plan["arm_order"]}
    deltas = {}
    for key, a, b in (("full_vs_none", "full", "none"), ("full_vs_old_skill", "full", "old_skill"),
                      ("pack_vs_full", "pack", "full"), ("pack_vs_none", "pack", "none")):
        if a in summary and b in summary:
            deltas[key] = delta(summary, a, b)
    shipped = "pack" if plan["mode"] == "composite" else "full"
    notes = ["composite pack check: not a promotion record"] if plan["mode"] == "composite" else []
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
    if plan["mode"] == "composite":
        # Which skills each case loaded, per arm: the number of runs that
        # loaded each one. Any load on a non_trigger case, and any skill but
        # the one under test, is cross-triggering to read before promotion.
        record["skill_loads"] = {arm: {c["id"]: dict(sorted(Counter(
            s for r in runs[arm][c["id"]] for s in set(r["chain"])).items()))
            for c in plan["cases"]} for arm in plan["arm_order"]}
        if "none" in summary:
            notes += [f"pack control gate: {w}" for w in control_failures(summary["pack"], summary["none"])]
        others = sorted({s for loads in record["skill_loads"]["pack"].values() for s in loads} - {plan["skill"]})
        notes.append(f"pack arm loaded other skills: {', '.join(others)}" if others
                     else "pack arm loaded no other skill")
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


def cmd_written_skill(args):
    """Prints the one skill directory a run wrote under a glob in its work
    tree, or why there is no usable one (exit 1)."""
    workdir, pattern = args
    safe_rel(pattern, "path")
    root = os.path.realpath(workdir)
    found = []
    for md in glob.glob(os.path.join(root, pattern, "SKILL.md")):
        d = os.path.dirname(md)
        if os.path.isfile(md) and inside(root, os.path.relpath(d, root)):
            found.append(d)
    found.sort()
    if len(found) != 1:
        rels = ", ".join(os.path.relpath(d, root) for d in found)
        print(f"expected one skill at {pattern}/SKILL.md, found {len(found)}" + (f": {rels}" if rels else ""))
        sys.exit(1)
    d = found[0]
    try:
        meta = skill_meta(os.path.join(d, "SKILL.md"))
    except Invalid as e:
        print(str(e).replace(root + os.sep, ""))
        sys.exit(1)
    name, base = meta["name"] or "", os.path.basename(d)
    if len(name) > 64 or not SKILL_NAME_RE.match(name):
        print(f"{os.path.relpath(d, root)}: name {name!r} is not a valid skill name")
        sys.exit(1)
    if name != base:
        print(f"{os.path.relpath(d, root)}: name {name!r} does not match its directory {base!r}")
        sys.exit(1)
    print(d)


def cmd_trigger_plan(args):
    """Lists the skill-triggering assertions of one or more cases (a case
    file, a list, or - for stdin) with the sessions each costs per run."""
    case_dir, src = args
    data = json.load(sys.stdin) if src == "-" else load_json(src)
    out = []
    for case in data if isinstance(data, list) else [data]:
        for i, a in enumerate(case.get("assertions", [])):
            if a.get("type") != "skill-triggering":
                continue
            qpath = os.path.join(os.path.realpath(case_dir), a["queries"])
            runs = a.get("runs", WRITTEN_SKILL_RUNS)
            out.append({"case": case["id"], "index": i, "path": a["path"], "queries": qpath,
                        "runs": runs, "threshold": a.get("threshold", WRITTEN_SKILL_THRESHOLD),
                        "sessions": len(load_queries(qpath, False)) * runs})
    dump_json(out)


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
        default_split = "negative" if manual_only else "all"
        split = q.get("split", default_split)
        if split not in SPLITS:
            raise Invalid(f"{where}: 'split' must be one of {', '.join(SPLITS)}")
        if split == "negative" and q["should_trigger"]:
            raise Invalid(f"{where}: negative-split queries must have should_trigger false")
        if manual_only and (split != "negative" or q["should_trigger"]):
            raise Invalid(f"{where}: a manual-only skill uses split 'negative' with should_trigger false")
        item = {"index": i, "query": q["query"], "should_trigger": q["should_trigger"],
                "split": split}
        if "fixture" in q:
            safe_rel(q["fixture"], f"{where}.fixture")
            files = os.path.join(os.path.dirname(os.path.abspath(path)), "files")
            if not os.path.isdir(os.path.join(files, q["fixture"])):
                raise Invalid(f"{where}: fixture directory not found: files/{q['fixture']}")
            item["fixture"] = q["fixture"]
        out.append(item)
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
    target = plan["skill"]
    with_skills = plan.get("with_skills") or []
    per_query, splits = [], {}
    models = Counter()
    all_others = Counter()
    for q in plan["queries"]:
        valid = triggered = other_runs = 0
        q_others = Counter()
        for rf in sorted(glob.glob(os.path.join(ws, f"q{q['index']}", "run-*", "result.json"))):
            r = load_json(rf)
            if r.get("model"):
                models[r["model"]] += 1
            if r.get("valid"):
                valid += 1
                triggered += 1 if r.get("triggered") else 0
                others = [s for s in (r.get("skill_chain") or []) if isinstance(s, str) and s != target]
                if others:
                    other_runs += 1
                    for s in set(others):
                        q_others[s] += 1
                        all_others[s] += 1
        rt = round(triggered / valid, 4) if valid else None
        other_rt = round(other_runs / valid, 4) if valid else None
        if rt is None:
            verdict = "inconclusive"
        elif with_skills and other_rt >= thr:
            verdict = "fail"
        elif q["should_trigger"]:
            verdict = "pass" if rt > thr else "fail"
        else:
            verdict = "pass" if rt < thr else "fail"
        row = dict(q, valid_runs=valid, triggered_runs=triggered, rate=rt, verdict=verdict)
        if with_skills:
            row["other_skills"] = dict(sorted(q_others.items()))
        per_query.append(row)
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
        "schema_version": 1, "pack": plan["pack"], "skill": target,
        "manual_only": plan["manual_only"], "harness": plan["harness"],
        "harness_version": plan.get("harness_version") or "unknown",
        "model": models.most_common(1)[0][0] if models else (plan.get("model_flag") or "unknown"),
        "plugin": plan["plugin"], "runs": plan["runs"], "threshold": thr, "splits": out_splits,
    }
    if with_skills:
        record["with_skills"] = with_skills
        record["other_skills_loaded"] = dict(sorted(all_others.items()))
    dump_json(record, os.path.join(ws, "triggering.json"))
    dump_json(per_query, os.path.join(ws, "query-results.json"))


# ---------------------------------------------------------------- report ----

def cmd_record(args):
    """Validates a workspace benchmark.json or triggering.json and merges a
    compact summary into <results_dir>/<pack>/<skill>.json (overwriting older
    skill trees in place)."""
    path, results_dir = args[0], args[1]
    date_arg = args[2] if len(args) > 2 else ""
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

    pack, skill, harness = rec["pack"], rec["skill"], rec["harness"]
    model = str(rec.get("model") or "unknown")

    if base == "benchmark.json":
        if rec.get("mode") == "composite":
            raise Invalid("a composite pack check is not a promotion record; keep it in its workspace")
        if rec.get("hooks_enabled") is not False:
            raise Invalid("hooks_enabled must be false")
        arms = rec.get("arms") or {}
        for arm, ident in arms.items():
            if arm != "none" and (not ident or not ident.get("skill_tree") or ident["skill_tree"] == "null"):
                raise Invalid(f"arms.{arm}.skill_tree is null: commit the skill and re-run")
        shipped = rec.get("shipped_arm")
        if shipped not in arms:
            raise Invalid("shipped_arm was not measured")
        tree = arms[shipped]["skill_tree"]
        stamp = rec["measured_at"]
        summary = rec.get("run_summary") or {}
        evals = rec.get("evals") or []
        s, n = summary.get(shipped, {}), summary.get("none")
        min_case_runs = min((e["arms"][a]["scored_runs"] for e in evals for a in arms), default=0)
        indeterminate = max(sum(e["arms"][a]["indeterminate"] for e in evals for a in arms),
                            sum(summary[a]["indeterminate_count"] for a in arms))
        needs_review = max(sum(e["arms"][a]["needs_review"] for e in evals for a in arms),
                           sum(summary[a]["needs_review_count"] for a in arms))
        payload_key = "benchmark"
        payload = {
            "shipped_arm": shipped,
            "pass_rate": s.get("pass_rate"),
            "none_pass_rate": n.get("pass_rate") if n else None,
            "scored_runs": s.get("scored_runs", 0),
            "min_case_runs": min_case_runs,
            "indeterminate": indeterminate,
            "needs_review": needs_review,
            "controls_passed": len(control_failures(s, n)) == 0,
        }
        desc_sha = None
        manual_only = None
    else:
        if rec.get("with_skills"):
            raise Invalid("a --with-skills routing check is not a solo triggering record; keep it in its workspace")
        p = rec.get("plugin") or {}
        if not p.get("skill_tree") or not p.get("description_sha256"):
            raise Invalid("plugin.skill_tree or plugin.description_sha256 is null: commit the skill and re-run")
        manual_only = bool(rec.get("manual_only"))
        splits = rec.get("splits") or {}
        if not splits:
            raise Invalid("triggering record has no splits")
        if manual_only and "negative" not in splits:
            raise Invalid("a manual-only skill's record needs a negative split")
        tree = p["skill_tree"]
        desc_sha = p["description_sha256"]
        stamp = rec.get("measured_at") or utc_now()
        queries = sum(s["queries"] for s in splits.values())
        passed = sum(s["passed"] for s in splits.values())
        inconclusive = sum(s["inconclusive"] for s in splits.values())
        all_passed = (
            queries > 0
            and all(s["queries"] > 0 and s["inconclusive"] == 0 and s["passed"] == s["queries"]
                    for s in splits.values())
        )
        payload_key = "triggering"
        payload = {
            "passed": passed,
            "queries": queries,
            "runs": rec.get("runs", 0),
            "inconclusive": inconclusive,
            "all_passed": all_passed,
        }

    date = date_arg or stamp[:10]
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", date):
        raise Invalid(f"bad date {date!r}")

    target = os.path.join(results_dir, pack, f"{skill}.json")
    doc = None
    if os.path.isfile(target):
        try:
            existing = load_json(target)
            if isinstance(existing, dict) and existing.get("skill_tree") == tree:
                doc = existing
        except (OSError, ValueError):
            doc = None
    if doc is None:
        doc = {"pack": pack, "skill": skill, "skill_tree": tree, "results": []}
    if desc_sha is not None:
        doc["description_sha256"] = desc_sha
        doc["manual_only"] = manual_only

    entries = list(doc.get("results") or [])
    entry = next((e for e in entries if e.get("model") == model and e.get("harness") == harness), None)
    if entry is None:
        entry = {"model": model, "harness": harness, "date": date}
        entries.append(entry)
    else:
        entry["date"] = date
    entry[payload_key] = payload
    entries.sort(key=lambda e: (str(e.get("model") or ""), str(e.get("harness") or "")))
    doc["results"] = entries

    os.makedirs(os.path.dirname(target), exist_ok=True)
    dump_json(doc, target)
    print(target)


def pct(x):
    return DASH if x is None else f"{round(100 * x)}%"


def cell(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def scoreboard_rows(results_dir):
    rows = []
    for path in sorted(glob.glob(os.path.join(results_dir, "*", "*.json"))):
        try:
            doc = load_json(path)
            pack, skill = doc["pack"], doc["skill"]
            entries = doc.get("results") or []
        except (OSError, ValueError, KeyError, TypeError):
            continue
        if not entries:
            continue
        b_entries = [e for e in entries if isinstance(e.get("benchmark"), dict)]
        t_entries = [e for e in entries if isinstance(e.get("triggering"), dict)]
        if b_entries:
            rates = " · ".join(
                f"{e.get('model', 'unknown')} {pct(e['benchmark'].get('pass_rate'))} vs "
                f"{pct(e['benchmark'].get('none_pass_rate'))}"
                for e in b_entries
            )
            controls = "pass" if all(e["benchmark"].get("controls_passed") for e in b_entries) else "fail"
        else:
            rates = controls = DASH
        if t_entries:
            ratios = [f"{e['triggering'].get('passed')}/{e['triggering'].get('queries')}" for e in t_entries]
            if len(set(ratios)) == 1:
                trig = ratios[0]
            else:
                trig = " · ".join(
                    f"{e.get('model', 'unknown')} {e['triggering'].get('passed')}/{e['triggering'].get('queries')}"
                    for e in t_entries
                )
        else:
            trig = DASH
        dates = [str(e.get("date") or "") for e in entries if e.get("date")]
        updated = max(dates) if dates else DASH
        rel = f"evals/results/{pack}/{skill}.json"
        rows.append("| " + " | ".join(cell(c) for c in (
            f"`{pack}/{skill}`", rates, controls, trig, updated,
        )) + f" | [{skill}.json]({rel}) |")
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
    "triggering": cmd_triggering, "record": cmd_record, "scoreboard": cmd_scoreboard,
    "written-skill": cmd_written_skill, "trigger-plan": cmd_trigger_plan,
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
