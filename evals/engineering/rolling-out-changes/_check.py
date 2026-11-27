"""Run a check snippet against the work tree in a fresh interpreter.

The snippet runs with the work tree as its cwd. The work tree comes first on
PYTHONPATH, then this directory (for _live.py). FIXTURE names the fixture
the run started from. A failed assert or any exception fails the case, and
its last line is the reason.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def run(root, fixture, code, timeout=120):
    env = dict(os.environ, PYTHONPATH=os.pathsep.join([root, HERE]),
               PYTHONDONTWRITEBYTECODE="1", PYTHONUNBUFFERED="1")
    code = f"FIXTURE = {os.path.join(HERE, 'files', fixture)!r}\n" + code
    try:
        p = subprocess.run([sys.executable, "-c", code], cwd=root, env=env, timeout=timeout,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except subprocess.TimeoutExpired:
        print("check timed out")
        sys.exit(1)
    except OSError as e:
        print(f"could not start python: {e}")
        sys.exit(1)
    lines = [ln for ln in p.stdout.decode("utf-8", "replace").splitlines() if ln.strip()]
    if p.returncode != 0:
        print(lines[-1][-300:] if lines else f"check exited {p.returncode}")
        sys.exit(1)
