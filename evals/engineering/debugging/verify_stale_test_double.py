"""Exit 0 when alerts go out as high priority against the real Gateway interface and the test double matches it."""
import os
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
DEADLINE = time.monotonic() + 110
env = dict(os.environ, PYTHONPATH=str(root), PYTHONDONTWRITEBYTECODE="1")

PROBE = r"""
import inspect, sys
from notify.gateway import Gateway, Receipt
from notify.service import NotificationService
from notify.users import User, UserDirectory


def fail(msg):
    print(msg)
    sys.exit(1)


SIG = inspect.signature(Gateway.send)
params = list(SIG.parameters.values())
shape = [(p.name, p.kind, p.default) for p in params]
want = [("self", inspect.Parameter.POSITIONAL_OR_KEYWORD, inspect.Parameter.empty),
        ("recipient", inspect.Parameter.POSITIONAL_OR_KEYWORD, inspect.Parameter.empty),
        ("body", inspect.Parameter.POSITIONAL_OR_KEYWORD, inspect.Parameter.empty),
        ("priority", inspect.Parameter.KEYWORD_ONLY, "normal")]
if shape != want:
    fail("Gateway.send no longer has the signature (recipient, body, *, priority='normal')")
if [f for f in Receipt.__dataclass_fields__] != ["id", "status"]:
    fail("Receipt is no longer a dataclass with id and status")


class StrictGateway:
    def __init__(self, status="queued"):
        self.calls = []
        self.status = status

    def send(self, *args, **kwargs):
        bound = SIG.bind(self, *args, **kwargs)
        bound.apply_defaults()
        args = dict(bound.arguments)
        args.pop("self")
        self.calls.append(args)
        return Receipt(id=f"m-{len(self.calls)}", status=self.status)


users = UserDirectory([User("u-1", "ada@example.com"), User("u-2", "ben@example.com", muted=True)])
gw = StrictGateway()
service = NotificationService(gw, users)
try:
    receipt = service.alert("u-1", "Disk almost full")
except Exception as e:
    fail(f"alert() fails against the real Gateway interface: {type(e).__name__}: {e}")
if gw.calls != [{"recipient": "ada@example.com", "body": "Disk almost full", "priority": "high"}]:
    fail(f"alert() sent {gw.calls}, expected one high priority message to ada@example.com")
if not isinstance(receipt, Receipt) or receipt.status != "queued":
    fail("alert() does not return the gateway's Receipt")

gw.calls.clear()
service.alert("u-2", "Password changed")
if [c.get("priority") for c in gw.calls] != ["high"]:
    fail("alert() to a muted user is not sent as high priority")

gw.calls.clear()
try:
    service.notify("u-1", "Weekly summary")
except Exception as e:
    fail(f"notify() fails against the real Gateway interface: {type(e).__name__}: {e}")
if gw.calls != [{"recipient": "ada@example.com", "body": "Weekly summary", "priority": "normal"}]:
    fail(f"notify() sent {gw.calls}, expected one normal priority message")
gw.calls.clear()
service.notify("u-2", "Weekly summary")
if gw.calls:
    fail("notify() messages a muted user")

rejected = NotificationService(StrictGateway(status="rejected"), users)
try:
    rejected.alert("u-1", "Disk almost full")
except Exception:
    pass
else:
    fail("alert() no longer reports a message the gateway did not queue")

try:
    import tests.fakes as fakes
except ImportError:
    fakes = None
fake_cls = getattr(fakes, "FakeGateway", None) if fakes else None
if fake_cls is not None:
    fake_sig = inspect.signature(fake_cls.send)
    probes = [(("ada@example.com", "hi"), {}),
              (("ada@example.com", "hi"), {"priority": "high"}),
              ((), {"recipient": "ada@example.com", "body": "hi"}),
              ((), {"recipient": "ada@example.com", "body": "hi", "priority": "low"})]
    for args, kwargs in probes:
        try:
            fake_sig.bind(None, *args, **kwargs)
        except TypeError:
            shown = ", ".join([repr(a) for a in args] + [f"{k}={v!r}" for k, v in kwargs.items()])
            fail(f"tests/fakes.py FakeGateway.send rejects a call the real Gateway accepts: send({shown})")
    try:
        fake = fake_cls()
        result = fake.send("ada@example.com", "hi", priority="high")
    except Exception as e:
        fail(f"tests/fakes.py FakeGateway.send fails on a valid call: {type(e).__name__}: {e}")
    if isinstance(result, dict) or getattr(result, "status", None) != "queued" or not hasattr(result, "id"):
        fail("tests/fakes.py FakeGateway.send does not return a Receipt-like object")
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
    fail(f"verifier could not inspect the service: {type(e).__name__}: {e}")
