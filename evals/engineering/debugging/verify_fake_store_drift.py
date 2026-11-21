"""Exit 0 when the service tests pass and the in-memory store behaves like SqliteUserStore."""
import os
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
DEADLINE = time.monotonic() + 110
env = dict(os.environ, PYTHONPATH=str(root), PYTHONDONTWRITEBYTECODE="1")

PROBE = r"""
import sys
from accounts.store import DuplicateEmail, SqliteUserStore, UserNotFound


def fail(msg):
    print(msg)
    sys.exit(1)


try:
    import tests.fakes as fakes
except ImportError:
    fakes = None
fake_cls = getattr(fakes, "InMemoryUserStore", None) if fakes else None
if fake_cls is None:
    sys.exit(0)

# Each step: (method, args); an int argument names the id returned by that earlier add.
SCRIPT = [("add", (" Ben@Example.com ", "Ben")), ("add", ("ada@example.com", "Ada")),
          ("add", ("ADA@example.com", "Ada Two")), ("add", ("ada@example.com", "Ada Three")),
          ("add", ("cy@example.com", "Cy")), ("add", ("dee@example.com", "Dee")),
          ("find_by_email", ("BEN@example.COM",)), ("find_by_email", ("  cy@example.com",)),
          ("find_by_email", ("nobody@example.com",)), ("get", (0,)), ("get", ("u-404",)),
          ("deactivate", (2,)), ("deactivate", ("u-404",)), ("get", (2,)), ("deactivate", (2,)),
          ("add", ("Cy@example.com", "Cy Again")), ("active_users", ()),
          ("deactivate", (0,)), ("active_users", ())]


def shape(value):
    if value is None:
        return None
    if isinstance(value, list):
        return [shape(v) for v in value]
    return (value.email, value.name, value.active)


def play(store):
    ids, seen = [], []
    for method, args in SCRIPT:
        args = tuple(ids[a] if isinstance(a, int) else a for a in args)
        try:
            value = getattr(store, method)(*args)
        except (UserNotFound, DuplicateEmail) as e:
            seen.append((method, args, "raises " + type(e).__name__))
            continue
        except Exception as e:
            seen.append((method, args, f"raises {type(e).__name__}: {e}"))
            continue
        if method == "add":
            ids.append(value.id)
            args = args[:1]
        seen.append((method, args, shape(value)))
    return seen


real = play(SqliteUserStore())
try:
    fake = play(fake_cls())
except Exception as e:
    fail(f"tests/fakes.py InMemoryUserStore cannot be driven like the real store: {type(e).__name__}: {e}")
for (method, args, want), (_, _, got) in zip(real, fake):
    if want != got:
        shown = ", ".join(repr(a) for a in args)
        fail(f"tests/fakes.py InMemoryUserStore.{method}({shown}) gives {got!r}, the real store gives {want!r}")
"""


def fail(msg):
    print(msg)
    sys.exit(1)


def budget(timeout):
    left = DEADLINE - time.monotonic()
    if left < 1:
        fail("verifier ran out of time")
    return min(timeout, left)


def run(argv, timeout):
    try:
        p = subprocess.run(argv, cwd=root, env=env, timeout=budget(timeout),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired:
        fail(f"{' '.join(argv[1:3])} timed out")
    out = p.stdout.decode("utf-8", "replace").strip().splitlines()
    err = [ln for ln in p.stderr.decode("utf-8", "replace").splitlines() if ln.strip()]
    return p.returncode, (out[-1] if out else ""), (err[-1] if err else "")


def main():
    rc, out, err = run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], 120)
    if rc != 0:
        fail("unit tests fail: " + (err or str(rc))[:200])
    rc, out, err = run([sys.executable, "-c", PROBE], 60)
    if rc != 0:
        fail((out or err or f"probe exited {rc}")[:300])
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except BaseException as e:
    fail(f"verifier could not inspect the store: {type(e).__name__}: {e}")
