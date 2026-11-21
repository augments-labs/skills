"""Apply pending migrations from migrations/ in filename order.

A deploy runs `python3 migrate.py "$DATABASE_URL"` once, before the new
build rolls out. Each file runs in one transaction and is recorded in
schema_migrations. On PostgreSQL each migration runs with a 5 s lock
timeout: one that cannot get its locks fails, and the deploy stops.
"""
import pathlib
import sys

from app.db import connect, dialect

MIGRATIONS = pathlib.Path(__file__).resolve().parent / "migrations"


def pending(conn):
    conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY)")
    conn.commit()
    done = {row[0] for row in conn.execute("SELECT name FROM schema_migrations")}
    return [p for p in sorted(MIGRATIONS.glob("*.sql")) if p.name not in done]


def migrate(conn):
    """Apply every pending migration and return the names applied."""
    applied = []
    for path in pending(conn):
        sql = path.read_text()
        if dialect(conn) == "postgresql":
            with conn:
                conn.execute("SET LOCAL lock_timeout = '5s'")
                conn.execute(sql)
                conn.execute("INSERT INTO schema_migrations (name) VALUES (?)", (path.name,))
        else:
            try:
                conn.executescript(
                    f"BEGIN;\n{sql}\n;\n"
                    f"INSERT INTO schema_migrations (name) VALUES ('{path.name}');\nCOMMIT;"
                )
            except Exception:
                conn.rollback()
                raise
        applied.append(path.name)
    return applied


if __name__ == "__main__":
    names = migrate(connect(sys.argv[1]))
    print("\n".join(names) if names else "nothing to apply")
