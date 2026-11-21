"""Apply pending migrations from migrations/ in filename order.

A deploy runs `python3 migrate.py "$DATABASE_URL"` once, before the new build
rolls out. Each file runs inside one transaction and is recorded in
schema_migrations. A file whose first line is `-- migrate:no-transaction`
runs outside a transaction instead, one statement at a time.
"""
import pathlib
import sys

MIGRATIONS = pathlib.Path(__file__).resolve().parent / "migrations"
NO_TRANSACTION = "-- migrate:no-transaction"


def split_statements(sql):
    """Split a file on semicolons, dropping comment-only chunks."""
    out = []
    for chunk in sql.split(";"):
        lines = [ln for ln in chunk.strip().splitlines() if not ln.strip().startswith("--")]
        if any(ln.strip() for ln in lines):
            out.append("\n".join(lines).strip())
    return out


def pending(conn):
    with conn.transaction():
        conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY)")
    done = {row[0] for row in conn.execute("SELECT name FROM schema_migrations").fetchall()}
    return [p for p in sorted(MIGRATIONS.glob("*.sql")) if p.name not in done]


def apply(conn, path):
    sql = path.read_text()
    if sql.startswith(NO_TRANSACTION):
        conn.autocommit = True
        try:
            for statement in split_statements(sql):
                conn.execute(statement)
            conn.execute("INSERT INTO schema_migrations (name) VALUES (%s)", (path.name,))
        finally:
            conn.autocommit = False
    else:
        with conn.transaction():
            conn.execute(sql)
            conn.execute("INSERT INTO schema_migrations (name) VALUES (%s)", (path.name,))


def main(url):
    import psycopg

    with psycopg.connect(url) as conn:
        for path in pending(conn):
            apply(conn, path)
            print("applied", path.name)


if __name__ == "__main__":
    main(sys.argv[1])
