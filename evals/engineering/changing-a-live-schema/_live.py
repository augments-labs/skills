"""Rebuild production as the fixture left it, and load the build running there."""
import importlib.util
import os
import pathlib
import sqlite3
import tempfile


def production_db(fixture):
    """A SQLite database with the fixture's migrations applied and recorded."""
    path = os.path.join(tempfile.mkdtemp(), "production.db")
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("CREATE TABLE schema_migrations (name TEXT PRIMARY KEY)")
    for f in sorted((pathlib.Path(fixture) / "migrations").glob("*.sql")):
        conn.executescript(f.read_text())
        conn.execute("INSERT INTO schema_migrations (name) VALUES (?)", (f.name,))
    conn.commit()
    return conn


def previous_build(fixture, rel="app/users.py"):
    """The module as the fixture had it: the build still serving traffic."""
    spec = importlib.util.spec_from_file_location("previous_build", pathlib.Path(fixture) / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def applied_migrations_unchanged(fixture):
    for f in sorted((pathlib.Path(fixture) / "migrations").glob("*.sql")):
        here = pathlib.Path("migrations") / f.name
        assert here.exists(), f"migration {f.name} already ran in production but was deleted or renamed"
        assert here.read_text() == f.read_text(), (
            f"migration {f.name} already ran in production but was edited")


def new_migrations(fixture):
    old = {f.name for f in (pathlib.Path(fixture) / "migrations").glob("*.sql")}
    return [p for p in sorted(pathlib.Path("migrations").glob("*.sql")) if p.name not in old]


def run_migrate(conn):
    import migrate
    try:
        migrate.migrate(conn)
    except Exception as e:
        raise AssertionError(f"migrate.py fails on the production schema: {type(e).__name__}: {e}")


def still_serves(label, fn):
    try:
        return fn()
    except (sqlite3.Error, ValueError, TypeError, KeyError) as e:
        raise AssertionError(
            f"after migrate.py, a replica still on the previous build fails to {label}: "
            f"{type(e).__name__}: {e}")


def name_of(user):
    assert user is not None, "get_user returned None for an existing user"
    for key in ("display_name", "fullname", "name"):
        if key in user:
            return user[key]
    raise AssertionError(f"get_user returns no name field: {sorted(user)}")
