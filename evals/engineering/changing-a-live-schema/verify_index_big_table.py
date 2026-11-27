"""index-big-table: the events index builds without blocking writes."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""

import contextlib, pathlib, re, sys, types
from _live import applied_migrations_unchanged, new_migrations
applied_migrations_unchanged(FIXTURE)
added = new_migrations(FIXTURE)
assert added, "no new migration file under migrations/"
ALREADY = [(p.name,) for p in sorted(pathlib.Path(FIXTURE, "migrations").glob("*.sql"))]
END = object()

class FakeConn:
    # Logs (sql, in_transaction) like psycopg 3: without autocommit, the first
    # statement opens a transaction that lasts until commit or rollback.
    def __init__(self):
        self.autocommit = False
        self.block = 0
        self.open = False
        self.rows = []
        self.log = []
    @contextlib.contextmanager
    def transaction(self):
        self.block += 1
        try:
            yield self
        finally:
            self.block -= 1
            if self.block == 0 and self.autocommit:
                self.log.append((END, False))
    def execute(self, sql, params=None):
        sql = str(sql)
        in_tx = self.block > 0 or not self.autocommit
        if not self.autocommit:
            self.open = True
        self.log.append((sql, in_tx))
        if not in_tx:
            self.log.append((END, False))
        self.rows = ALREADY if re.match(r"\s*select\b[^;]*schema_migrations", sql, re.I) else []
        return self
    def fetchall(self):
        return list(self.rows)
    def fetchone(self):
        return self.rows[0] if self.rows else None
    def __iter__(self):
        return iter(self.fetchall())
    def cursor(self, *a, **k):
        return self
    def commit(self):
        self.open = False
        self.log.append((END, False))
    def rollback(self):
        self.commit()
    def close(self):
        pass
    def __enter__(self):
        return self
    def __exit__(self, *exc):
        self.commit()

conn = FakeConn()
fake = types.ModuleType("psycopg")
fake.connect = lambda *a, **k: conn
sys.modules["psycopg"] = fake
import migrate
try:
    migrate.main("postgresql://ledger-primary/ledger")
except Exception:
    conn = FakeConn()
    for path in added:
        migrate.apply(conn, path)

def statements(text):
    return [s.strip() for s in re.sub(r"--[^\n]*", "", text).split(";") if s.strip()]

hits = [(text, in_tx) for text, in_tx in conn.log
        if text is not END and re.search(r"create\s+(unique\s+)?index\b[^;]*\bon\s+(only\s+)?(public\.)?events\b[^;]*\(\s*account_id", text, re.I | re.S)]
assert hits, "no new migration creates an index on events led by account_id"
for text, in_tx in hits:
    assert re.search(r"index\s+concurrently", text, re.I), (
        "CREATE INDEX on events without CONCURRENTLY blocks the 4,000 inserts a second for the whole build")
    assert not in_tx, (
        "migrate.py runs the CREATE INDEX CONCURRENTLY inside a transaction, where PostgreSQL refuses it")
    assert len(statements(text)) == 1, (
        "CREATE INDEX CONCURRENTLY is sent with other statements in one call, which PostgreSQL runs as one transaction")
"""

_check.run(os.path.abspath(sys.argv[1]), "ledger", CHECK)
