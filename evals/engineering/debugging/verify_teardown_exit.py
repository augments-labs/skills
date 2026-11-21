"""Exit 0 when `bash test.sh` passes for the right reason and the ledger still journals."""
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
DEADLINE = time.monotonic() + 110


def fail(msg):
    print(msg)
    sys.exit(1)


def budget(timeout):
    left = DEADLINE - time.monotonic()
    if left < 1:
        fail("verifier ran out of time")
    return min(timeout, left)


def run(argv, cwd, timeout=90, env=None):
    try:
        p = subprocess.run(argv, cwd=cwd, env=env, timeout=budget(timeout),
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except subprocess.TimeoutExpired:
        fail(f"{' '.join(argv)} timed out")
    except OSError as e:
        fail(f"{' '.join(argv)} could not start: {e}")
    return p.returncode, p.stdout.decode("utf-8", "replace")


try:
    script = (root / "test.sh").read_text(encoding="utf-8")
except OSError:
    fail("test.sh is missing")
if not re.search(r"^\s*set\s+-[a-z]*e", script, re.M):
    fail("test.sh no longer stops on the first error (set -e removed)")
if re.search(r"\|\|\s*(true|:)(\s|$)|\bset\s+\+e\b|^\s*exit\s+0\b|\btrap\b[^\n]*\bexit\s+0", script, re.M):
    fail("test.sh masks a failing step")
if not re.search(r"tests[./]cleanup", script):
    fail("test.sh no longer runs the cleanup step")

rc, out = run(["bash", "test.sh"], root)
if rc != 0:
    fail(f"bash test.sh exited {rc}")
if not re.search(r"\b8 passed\b", out):
    fail("bash test.sh does not report 8 passed tests")
if (root / ".test-tmp").exists():
    fail(".test-tmp/ is left behind after bash test.sh")

probe = (
    "import sys\n"
    "from pathlib import Path\n"
    "from ledger import Ledger\n"
    "d = Path(sys.argv[1])\n"
    "book = Ledger(d / 'main.jsonl')\n"
    "book.append('acct-1', 100)\n"
    "j = d / 'journal.wal'\n"
    "sys.exit(0 if j.is_file() and '\"acct-1\"' in j.read_text() else 1)\n"
)
with tempfile.TemporaryDirectory() as d:
    env = dict(os.environ, PYTHONPATH=str(root), PYTHONDONTWRITEBYTECODE="1")
    rc, out = run([sys.executable, "-c", probe, d], d, timeout=20, env=env)
    if rc != 0:
        fail("the ledger no longer writes journal.wal next to its data file: " + out.strip()[-200:])
sys.exit(0)
