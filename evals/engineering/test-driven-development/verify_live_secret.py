"""Exit 0 when the live-secret rule flags live keys (24+ characters after the
prefix), passes test keys and short near-misses, masks the key, and the work
tree's own tests catch every planted detector bug."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "_mutation", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mutation.py"))
mutation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mutation)

HIDDEN = r'''
import sys
sys.path.insert(0, sys.argv[1])
from cfglint.engine import lint_text

K24 = "sk_live_" + "aB3dE5gH7jK9mN1pQ3sT5vW7"
K40 = "sk_live_" + "Zy9Xw8Vu7Ts6Rq5Po4Nm3Lk2Ji1Hg0FeDcBa987"
problems = []

def secrets(text):
    try:
        return [(f.line, f.message) for f in lint_text(text) if f.rule == "live-secret"]
    except Exception as exc:
        return "raised " + type(exc).__name__ + ": " + str(exc)

def expect(label, text, want):
    got = secrets(text)
    if got != want:
        problems.append(f"{label}: got {got!r}, want {want!r}")

expect("24-character live key", f"payments:\n  key: {K24}\n", [(2, "live secret key ending in " + K24[-4:])])
expect("40-character live key", f"key: {K40}\n", [(1, "live secret key ending in " + K40[-4:])])
expect("two keys on one line", f"a: {K24} b: {K40}\n",
       [(1, "live secret key ending in " + K24[-4:]), (1, "live secret key ending in " + K40[-4:])])
expect("test-mode key", "key: sk_test_" + "aB3dE5gH7jK9mN1pQ3sT5vW7xY\n", [])
expect("23 characters after the prefix", "key: sk_live_" + "aB3dE5gH7jK9mN1pQ3sT5vW\n", [])
expect("prefix alone", "key: sk_live_\n", [])
for p in problems:
    print("FAIL:", p)
sys.exit(1 if problems else 0)
'''

TEMPLATE = '''
import re
import cfglint.rules.secrets as _m
from cfglint.model import Finding
PATTERN = re.compile(r"__PATTERN__")
def check(self, lines):
    out = []
    for n, line in enumerate(lines, start=__START__):
        for m in __FIND__:
            out.append(Finding(n, "live-secret", "live secret key ending in " + __SHOW__))
    return out
_m.LiveSecret.check = check
'''
GOOD = {"__PATTERN__": "sk_live_[A-Za-z0-9]{24,}", "__START__": "1",
        "__FIND__": "PATTERN.finditer(line)", "__SHOW__": "m.group()[-4:]"}


def patch(**changes):
    src = TEMPLATE
    for key, value in dict(GOOD, **changes).items():
        src = src.replace(key, value)
    return src


MUTANTS = {
    "test-mode keys (sk_test_) are flagged": patch(__PATTERN__="sk_(?:live|test)_[A-Za-z0-9]{24,}"),
    "a key with 23 characters after the prefix is flagged": patch(__PATTERN__="sk_live_[A-Za-z0-9]{23,}"),
    "a key longer than 24 characters is missed": patch(
        __PATTERN__="sk_live_[A-Za-z0-9]{24}(?![A-Za-z0-9])"),
    "the message shows the whole key": patch(__SHOW__="m.group()"),
    "line numbers are 0-based": patch(__START__="0"),
    "only the first key on a line is reported": patch(
        __FIND__="[m for m in [PATTERN.search(line)] if m]"),
}


def check(workdir):
    return mutation.hidden(workdir, HIDDEN) + mutation.suite_catches(workdir, patch(), MUTANTS)


if __name__ == "__main__":
    mutation.main(check)
