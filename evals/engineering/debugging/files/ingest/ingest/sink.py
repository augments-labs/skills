import os
import sqlite3


def write_records(records, db_path=None):
    """Store records in SQLite, replacing rows that have the same id."""
    db_path = db_path or os.environ.get("INGEST_DB", ":memory:")
    with sqlite3.connect(db_path) as db:
        db.execute("CREATE TABLE IF NOT EXISTS payments "
                   "(id TEXT PRIMARY KEY, name TEXT, city TEXT, amount TEXT, ts TEXT)")
        db.executemany(
            "INSERT OR REPLACE INTO payments VALUES (?, ?, ?, ?, ?)",
            [(r.id, r.name, r.city, str(r.amount), r.ts.isoformat()) for r in records],
        )
    return len(records)
