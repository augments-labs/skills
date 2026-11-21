"""Exit 0 when the refactored describe() still returns exactly the original text
(or raises the same error) on a battery of inputs, and the work tree's own tests
catch each decision the original makes being changed."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "_mutation", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mutation.py"))
mutation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mutation)

ORIGINAL = 'def describe(seconds):\n    """Describe an elapsed time for display, e.g. "2 hours and 5 minutes"."""\n    if seconds is None:\n        return "-"\n    if seconds < 0:\n        raise ValueError(f"elapsed time cannot be negative: {seconds}")\n    if seconds < 1:\n        return "just now"\n    total = round(seconds)\n    parts = []\n    days = total // 86400\n    rest = total - days * 86400\n    hours = rest // 3600\n    rest = rest - hours * 3600\n    minutes = rest // 60\n    secs = rest - minutes * 60\n    for amount, unit in ((days, "day"), (hours, "hour"), (minutes, "minute"), (secs, "second")):\n        if amount == 0:\n            continue\n        if amount == 1:\n            parts.append(f"1 {unit}")\n        else:\n            parts.append(f"{amount} {unit}s")\n        if len(parts) == 2:\n            break\n    if len(parts) == 1:\n        return parts[0]\n    return parts[0] + " and " + parts[1]\n'

HIDDEN = r"""
import random
import sys
sys.path.insert(0, sys.argv[1])
from humanize.duration import describe

ref = {}
exec(ORIGINAL_SRC, ref)

def outcome(fn, x):
    try:
        return ("ok", fn(x))
    except Exception as exc:
        return ("raised", type(exc).__name__, str(exc))

rng = random.Random(11)
inputs = [None, 0, 0.0, 0.4, 0.5, 0.6, 0.999, 1, 1.5, 2.5, 3.5, 59.5, 60, 61, 119.5, 3599.5, 3600,
          3601, 3660, 3661, 7322, 86399, 86400, 86401, 86460, 90000, 90061, 172800, 10**7, -1, -0.5]
inputs += [rng.randint(0, 400000) for _ in range(500)]
inputs += [rng.randint(0, 400000) + 0.5 for _ in range(200)]
inputs += [rng.choice((1, 60, 3600, 86400)) * rng.randint(1, 3) + rng.choice((0, 1, 60, 3600)) for _ in range(200)]
problems = []
for x in inputs:
    got, want = outcome(describe, x), outcome(ref["describe"], x)
    if got != want:
        problems.append(f"describe({x!r}) gave {got!r}, the original gave {want!r}")
    if len(problems) >= 3:
        break
for p in problems:
    print("FAIL:", p)
sys.exit(1 if problems else 0)
""".replace("ORIGINAL_SRC", repr(ORIGINAL))


def variant(*edits):
    src = ORIGINAL
    for old, new in edits:
        if src.count(old) != 1:
            raise SystemExit(f"mutant edit does not apply once: {old!r}")
        src = src.replace(old, new)
    return src + '\nimport humanize.duration as _m\nswap(_m, "describe", describe)\n'


MUTANTS = {
    "half seconds round up instead of to even": variant(
        ("total = round(seconds)", "total = int(seconds + 0.5)")),
    "'just now' is decided after rounding": variant(
        ('    if seconds < 1:\n        return "just now"\n    total = round(seconds)\n',
         '    total = round(seconds)\n    if total < 1:\n        return "just now"\n')),
    "a zero unit between two others ends the text": variant(
        ("        if amount == 0:\n            continue\n",
         "        if amount == 0:\n            if parts:\n                break\n            continue\n")),
    "three units are shown instead of two": variant(
        ("if len(parts) == 2:", "if len(parts) == 3:"),
        ('return parts[0] + " and " + parts[1]', 'return ", ".join(parts[:-1]) + " and " + parts[-1]')),
    "a single unit reads 'a' instead of '1'": variant(
        ('parts.append(f"1 {unit}")', 'parts.append(f"a {unit}")')),
    "an unknown time shows as blank instead of '-'": variant(
        ('return "-"', 'return ""')),
    "a negative time reads 'just now' instead of raising": variant(
        ('raise ValueError(f"elapsed time cannot be negative: {seconds}")', 'return "just now"')),
}


def check(workdir):
    return mutation.hidden(workdir, HIDDEN) + mutation.suite_catches(workdir, variant(), MUTANTS)


if __name__ == "__main__":
    mutation.main(check)
