"""Exit 0 when the importer takes the failed batch and similar ones without dropping or mangling records."""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
DEADLINE = time.monotonic() + 110
env = dict(os.environ, PYTHONPATH=str(root), PYTHONDONTWRITEBYTECODE="1")
env.pop("INGEST_DB", None)


def fail(msg):
    print(msg)
    sys.exit(1)


def budget(timeout):
    left = DEADLINE - time.monotonic()
    if left < 1:
        fail("verifier ran out of time")
    return min(timeout, left)


def run(argv, timeout=20):
    try:
        p = subprocess.run(argv, cwd=root, env=env, timeout=budget(timeout),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired:
        fail(f"{' '.join(argv[:3])} timed out")
    except OSError as e:
        fail(f"could not start {argv[0]}: {e}")
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


def tail(text):
    lines = [ln for ln in text.strip().splitlines() if ln.strip()]
    return lines[-1][-200:] if lines else ""


DUMP = r"""
import json, sys
from ingest import load_file
out = []
for r in load_file(sys.argv[1]):
    ts = r.ts
    out.append({"id": r.id, "name": r.name, "city": r.city, "amount": str(r.amount),
                "ts": ts.isoformat(), "utc": ts.utcoffset() is not None and
                ts.utcoffset().total_seconds() == 0,
                "epoch": ts.timestamp() if ts.utcoffset() is not None else None})
print(json.dumps(out))
"""


def load(path):
    rc, out, err = run([sys.executable, "-c", DUMP, str(path)])
    if rc != 0:
        fail(f"load_file({Path(path).name}) raised: {tail(err)}")
    try:
        return json.loads(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        fail(f"load_file({Path(path).name}) printed unexpected output")


def cli(path, expect):
    rc, out, err = run([sys.executable, "-m", "ingest", str(path)])
    if rc != 0:
        fail(f"python3 -m ingest {Path(path).name} exited {rc}: {tail(err)}")
    m = re.search(r"imported (\d+) records", out)
    if not m or int(m.group(1)) != expect:
        fail(f"python3 -m ingest {Path(path).name} did not report {expect} records: {tail(out)}")


def by_id(rows):
    return {r["id"]: r for r in rows}


def epoch(y, mo, d, h, mi, s, off_minutes=0):
    from datetime import datetime, timedelta, timezone
    return datetime(y, mo, d, h, mi, s, tzinfo=timezone(timedelta(minutes=off_minutes))).timestamp()


def check_second(row, expected, label):
    if row["epoch"] is None:
        fail(f"{label}: timestamp lost its UTC offset ({row['ts']})")
    if int(row["epoch"] // 1) != int(expected):
        fail(f"{label}: timestamp {row['ts']} is not the second in the batch")


def main():
    batch = root / "fixtures" / "failed_batch.jsonl"
    if not batch.is_file():
        fail("fixtures/failed_batch.jsonl is missing")
    raw_lines = [ln for ln in batch.read_bytes().splitlines() if ln.strip()]
    if len(raw_lines) != 40:
        fail("fixtures/failed_batch.jsonl no longer holds the 40 original records")
    if b"Ren\xe9 Dubois" not in raw_lines[28] or b"23:59:59.250+00:00" not in raw_lines[11]:
        fail("fixtures/failed_batch.jsonl was edited")

    cli(batch, 40)
    rows = load(batch)
    if len(rows) != 40:
        fail(f"load_file returned {len(rows)} of 40 records")
    ids = by_id(rows)
    r12 = ids.get("p-0301-012")
    if r12 is None:
        fail("record p-0301-012 was dropped")
    check_second(r12, epoch(2026, 3, 1, 23, 59, 59), "line 12")
    r29 = ids.get("p-0301-029")
    if r29 is None:
        fail("record p-0301-029 was dropped")
    if not r29["name"].startswith("Ren") or not r29["name"].endswith(" Dubois") or len(r29["name"]) != 11:
        fail(f"line 29 name came back as {r29['name']!r}")
    if r29["city"] != "Gdansk" or r29["amount"] != "30.05":
        fail("line 29 lost its other fields")

    ok = root / "fixtures" / "batch_ok.jsonl"
    cli(ok, 12)
    ok_rows = by_id(load(ok))
    if ok_rows.get("p-0227-005", {}).get("name") != "Zoë Novak":
        fail("a valid UTF-8 name in batch_ok.jsonl no longer reads back unchanged")

    hidden = [
        {"id": "h-1", "name": "Anna Berg", "city": "Oslo", "amount": 12.5, "ts": "2026-03-02T08:15:30.123456+00:00"},
        {"id": "h-2", "name": "Tomas Ruiz", "city": "Vigo", "amount": 7, "ts": "2026-03-02T09:00:01Z"},
        {"id": "h-3", "name": "Lars Holm", "city": "@@CITY@@", "amount": 40.1, "ts": "2026-03-02T10:20:30+01:00"},
        {"id": "h-4", "name": "Søren Ølsen", "city": "Aarhus", "amount": 3.25, "ts": "2026-03-02T11:11:11.500Z"},
        {"id": "h-5", "name": "Mei Lin", "city": "Ipoh", "amount": 99.99, "ts": "2026-03-02T23:59:59.999999-05:00"},
        {"id": "h-6", "name": "Ola Nordin", "city": "Bergen", "amount": 1, "ts": "2026-03-02T12:00:00+00:00"},
    ]
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "hidden_batch.jsonl"
        data = b"\n".join(json.dumps(r, ensure_ascii=False).encode("utf-8") for r in hidden) + b"\n"
        data = data.replace(b"@@CITY@@", b"M\xfcnchen")
        path.write_bytes(data)
        cli(path, len(hidden))
        got = by_id(load(path))
    for r in hidden:
        if r["id"] not in got:
            fail(f"a similar batch dropped record {r['id']}")
    check_second(got["h-1"], epoch(2026, 3, 2, 8, 15, 30), "microsecond timestamp")
    check_second(got["h-2"], epoch(2026, 3, 2, 9, 0, 1), "Z timestamp")
    check_second(got["h-4"], epoch(2026, 3, 2, 11, 11, 11), "fractional Z timestamp")
    check_second(got["h-5"], epoch(2026, 3, 2, 23, 59, 59, -300), "negative offset timestamp")
    city = got["h-3"]["city"]
    if not (city.startswith("M") and city.endswith("nchen") and len(city) == 7):
        fail(f"a non UTF-8 byte in city came back as {city!r}")
    if got["h-4"]["name"] != "Søren Ølsen":
        fail(f"a valid UTF-8 name came back as {got['h-4']['name']!r}")

    rc, out, err = run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], timeout=60)
    if rc != 0:
        fail("unit tests fail: " + tail(err))
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except BaseException as e:
    fail(f"verifier could not inspect the importer: {type(e).__name__}: {e}")
