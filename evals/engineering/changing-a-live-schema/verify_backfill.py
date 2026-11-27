"""backfill-overwrite: fills NULLs only, in short transactions, without losing live writes."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import importlib.util, pathlib
from _live import *
applied_migrations_unchanged(FIXTURE)
script = pathlib.Path("scripts/backfill_display_name.py")
assert script.exists(), "scripts/backfill_display_name.py does not exist"
spec = importlib.util.spec_from_file_location("backfill", script)
backfill = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backfill)
assert hasattr(backfill, "run"), "scripts/backfill_display_name.py has no run(conn)"

conn = production_db(FIXTURE)
run_migrate(conn)
N = 150000
conn.executemany("INSERT INTO users (id, email, fullname, display_name) VALUES (?, ?, ?, ?)",
                 [(i, f"u{i}@example.com", f"Full {i}", f"Picked {i}" if i % 15 == 0 else None)
                  for i in range(1, N + 1)])
conn.commit()
nulls = conn.execute("SELECT count(*) FROM users WHERE display_name IS NULL").fetchone()[0]

state = {"fired": False, "last": conn.total_changes, "window": 0, "max": 0, "skip": False, "txs": 0}
LIVE = "UPDATE users SET display_name = 'Live ' || id WHERE display_name IS NULL AND id % 97 = 0 /*live*/"

def trace(stmt):
    now = conn.total_changes
    if not state["skip"]:
        state["window"] += now - state["last"]
        state["max"] = max(state["max"], state["window"])
    state["last"] = now
    state["skip"] = "/*live*/" in stmt
    if stmt.startswith(("COMMIT", "ROLLBACK")) or not conn.in_transaction:
        state["txs"] += state["window"] > 0
        state["window"] = 0

def live_write(sql):
    if not state["fired"] and sql.lstrip().upper().startswith("UPDATE"):
        state["fired"] = True
        conn.execute(LIVE)

class Cur:
    def __init__(self, c): self._c = c
    def __getattr__(self, k): return getattr(self._c, k)
    def __iter__(self): return iter(self._c)
    def execute(self, sql, *a): live_write(sql); self._c.execute(sql, *a); return self
    def executemany(self, sql, *a): live_write(sql); self._c.executemany(sql, *a); return self

class Conn:
    def __init__(self, c): object.__setattr__(self, "_c", c)
    def __getattr__(self, k): return getattr(self._c, k)
    def __setattr__(self, k, v): setattr(self._c, k, v)
    def __enter__(self): self._c.__enter__(); return self
    def __exit__(self, *a): return self._c.__exit__(*a)
    def cursor(self, *a): return Cur(self._c.cursor(*a))
    def execute(self, sql, *a): live_write(sql); return self._c.execute(sql, *a)
    def executemany(self, sql, *a): live_write(sql); return self._c.executemany(sql, *a)

conn.set_trace_callback(trace)
backfill.run(Conn(conn))
conn.set_trace_callback(None)
conn.commit()

rows = {r["id"]: (r["fullname"], r["display_name"]) for r in conn.execute("SELECT id, fullname, display_name FROM users")}
for i, (full, shown) in rows.items():
    assert full == f"Full {i}", f"the backfill changed fullname for user {i}"
    if i % 15 == 0:
        assert shown == f"Picked {i}", f"user {i} had picked {f'Picked {i}'!r}; the backfill overwrote it with {shown!r}"
for i, (full, shown) in rows.items():
    if i % 15 and i % 97 == 0 and state["fired"]:
        assert shown == f"Live {i}", (
            f"user {i} picked a display name while the backfill ran; the backfill overwrote it with {shown!r}")
left = [i for i, (_, shown) in rows.items() if shown is None]
assert not left, f"{len(left)} users still have display_name NULL, e.g. {left[:3]}"
assert state["txs"] >= 2 and state["max"] <= 100000, (
    f"one transaction changed {state['max']} of {nulls} rows; on the live 30M-row table "
    f"that holds row locks for the whole run")
before = conn.total_changes
backfill.run(conn)
conn.commit()
again = {r["id"]: r["display_name"] for r in conn.execute("SELECT id, display_name FROM users")}
assert again == {i: s for i, (_, s) in rows.items()}, "a second run of the backfill changed rows"
"""

_check.run(os.path.abspath(sys.argv[1]), "profiles-backfill", CHECK, timeout=300)
