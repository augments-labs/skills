"""Database connections.

Production runs on PostgreSQL; tests and local runs use SQLite. Write SQL
with `?` placeholders, in the subset both engines accept. Rows index by
position or by column name on both.
"""
import sqlite3


class _Row(tuple):
    def __new__(cls, names, values):
        row = super().__new__(cls, values)
        row._names = names
        return row

    def __getitem__(self, key):
        if isinstance(key, str):
            key = self._names.index(key)
        return tuple.__getitem__(self, key)

    def keys(self):
        return list(self._names)


def _row_factory(cursor):
    names = [c.name for c in cursor.description or ()]
    return lambda values: _Row(names, values)


class _PgConnection:
    """A psycopg connection that takes `?` placeholders."""

    def __init__(self, raw):
        self._raw = raw

    def execute(self, sql, params=()):
        return self._raw.execute(sql.replace("?", "%s"), params)

    def commit(self):
        self._raw.commit()

    def rollback(self):
        self._raw.rollback()

    def close(self):
        self._raw.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, *exc):
        if exc_type is None:
            self.commit()
        else:
            self.rollback()


def connect(url):
    if url.startswith("postgresql://"):
        import psycopg

        return _PgConnection(psycopg.connect(url, row_factory=_row_factory))
    conn = sqlite3.connect(url.removeprefix("sqlite:///"))
    conn.row_factory = sqlite3.Row
    return conn


def dialect(conn):
    return "postgresql" if isinstance(conn, _PgConnection) else "sqlite"
