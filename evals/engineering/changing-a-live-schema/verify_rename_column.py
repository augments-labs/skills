"""rename-column: old and new builds both work during the rollout."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _live import *
applied_migrations_unchanged(FIXTURE)
old = previous_build(FIXTURE)
conn = production_db(FIXTURE)
ada = old.create_user(conn, "ada@example.com", "Ada Lovelace")
run_migrate(conn)
cols = {r[1] for r in conn.execute("PRAGMA table_info(users)")}
assert "display_name" in cols, f"users has no display_name column after migrate.py: {sorted(cols)}"

from app import users as new
alan = new.create_user(conn, "alan@example.com", "Alan Turing")
row = conn.execute("SELECT display_name FROM users WHERE id = ?", (alan,)).fetchone()
assert row["display_name"] == "Alan Turing", f"the new build stores display_name={row['display_name']!r}"

grace = still_serves("create a user", lambda: old.create_user(conn, "grace@example.com", "Grace Hopper"))
still_serves("rename a user", lambda: old.rename_user(conn, ada, "Ada King"))
seen = still_serves("read a user", lambda: old.get_user(conn, alan))
assert seen["fullname"] == "Alan Turing", (
    f"a user the new build created reads as fullname={seen['fullname']!r} on the previous build")
new.rename_user(conn, alan, "A. M. Turing")
assert old.get_user(conn, alan)["fullname"] == "A. M. Turing", (
    "a rename on the new build is invisible to replicas on the previous build")
still_serves("rename a user", lambda: old.rename_user(conn, alan, "Alan M. Turing"))

for uid, want, how in [
    (ada, "Ada King", "an existing user renamed by the previous build"),
    (grace, "Grace Hopper", "a user the previous build created after migrate.py"),
    (alan, "Alan M. Turing", "a user the new build created, then the previous build renamed"),
]:
    got = name_of(new.get_user(conn, uid))
    assert got == want, f"the new build shows {got!r} for {how}; want {want!r}"
"""

_check.run(os.path.abspath(sys.argv[1]), "profiles", CHECK)
