"""Shared by the verifiers. A verifier loads this file by path (they run with
`python3 -I`, so a plain import would not find it).

Two checks:
- hidden(): run grader-owned checks against the work tree's own code.
- suite_catches(): run the work tree's own test suite (the README's unittest
  command) with one function or class swapped for a correct reference, then
  for each mutant. The suite must pass on the reference and fail on every
  mutant: that is what "the tests pin this behavior" means.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

MARK = "@@SUITE@@"

RUNNER = r'''
import io, json, os, sys, unittest
tree = os.path.realpath(sys.argv[1])
sys.path.insert(0, tree)
os.chdir(tree)

def swap(module, name, new):
    """Replace module.name, and every alias of it already imported from the tree."""
    old = getattr(module, name)
    setattr(module, name, new)
    for m in list(sys.modules.values()):
        f = os.path.realpath(getattr(m, "__file__", None) or "/nonexistent")
        if not f.startswith(tree + os.sep):
            continue
        for k, v in list(vars(m).items()):
            if v is old:
                setattr(m, k, new)

patch = sys.stdin.read()
if patch:
    exec(compile(patch, "<patch>", "exec"), {"swap": swap, "__name__": "patch"})
stream = io.StringIO()
suite = unittest.defaultTestLoader.discover("tests", top_level_dir=".")
result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
sys.stdout.write("\n" + "__MARK__" + json.dumps({
    "ok": result.wasSuccessful(), "run": result.testsRun,
    "failures": len(result.failures), "errors": len(result.errors),
    "skipped": len(result.skipped), "log": stream.getvalue()[-2500:]}) + "\n")
'''.replace("__MARK__", MARK)


def _env():
    env = {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def _copy_tree(workdir):
    base = tempfile.mkdtemp()
    tree = os.path.join(base, "tree")
    shutil.copytree(workdir, tree, ignore=shutil.ignore_patterns(".git", "__pycache__"))
    return base, tree


def run_suite(tree, patch="", timeout=120):
    """Run the tree's unittest suite with `patch` applied first. Returns a dict."""
    try:
        p = subprocess.run([sys.executable, "-I", "-B", "-c", RUNNER, tree], cwd=tree, env=_env(),
                           input=patch.encode(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"ok": False, "run": 0, "crash": "timed out"}
    out = p.stdout.decode("utf-8", "replace")
    if MARK not in out:
        return {"ok": False, "run": 0, "crash": out[-1500:]}
    return json.loads(out.rsplit(MARK, 1)[1].strip().splitlines()[0])


def suite_catches(workdir, reference, mutants):
    """`reference` is patch source; `mutants` maps a name to patch source.
    Returns a list of problems (empty when the suite passes on the reference and
    fails on every mutant)."""
    problems = []
    base, tree = _copy_tree(workdir)
    try:
        ref = run_suite(tree, reference)
        if not ref.get("ok") or not ref.get("run"):
            problems.append("the test suite does not pass with a correct implementation swapped in "
                            "(it tests something other than the requested behavior, or does not run): "
                            + (ref.get("crash") or ref.get("log", ""))[-1200:])
            return problems
        for name, src in mutants.items():
            res = run_suite(tree, src)
            if res.get("ok"):
                problems.append(f"the test suite still passes with this bug planted: {name}")
    finally:
        shutil.rmtree(base, ignore_errors=True)
    return problems


def hidden(workdir, child_src, timeout=120):
    """Run grader-owned checks (child_src prints FAIL lines and exits 1) on the work tree's code."""
    base, tree = _copy_tree(workdir)
    try:
        p = subprocess.run([sys.executable, "-I", "-B", "-c", child_src, tree], cwd=tree, env=_env(),
                           stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout)
        out = p.stdout.decode("utf-8", "replace").strip()
        return [] if p.returncode == 0 else [out[-2000:] or f"hidden checks exited {p.returncode}"]
    except subprocess.TimeoutExpired:
        return ["hidden checks timed out"]
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main(check):
    """Entry point for a verifier: check(workdir) returns a list of problems."""
    try:
        problems = check(os.path.abspath(sys.argv[1]))
    except BaseException as exc:  # a crash in the code under test is a failure
        problems = ["verifier could not check the work tree: %s: %s" % (type(exc).__name__, exc)]
    for p in problems:
        print("FAIL:", p)
    sys.exit(1 if problems else 0)
