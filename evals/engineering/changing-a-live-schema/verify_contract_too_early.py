"""contract-too-early: the build in production keeps working; the new one drops fullname use."""
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

grace = still_serves("create a user", lambda: old.create_user(conn, "grace@example.com", "Grace Hopper"))
still_serves("rename a user", lambda: old.rename_user(conn, ada, "Ada King"))
still_serves("read a user", lambda: old.get_user(conn, grace))

from app import users as new
alan = new.create_user(conn, "alan@example.com", "Alan Turing")
new.rename_user(conn, alan, "A. M. Turing")
cols = {r[1] for r in conn.execute("PRAGMA table_info(users)")}
if "fullname" in cols:
    row = conn.execute("SELECT fullname FROM users WHERE id = ?", (alan,)).fetchone()
    assert row["fullname"] is None, (
        f"the new build still writes fullname ({row['fullname']!r}); the request was to stop using it")
    conn.execute("UPDATE users SET fullname = 'stale' WHERE id = ?", (ada,))
    conn.commit()
for uid, want in [(ada, "Ada King"), (grace, "Grace Hopper"), (alan, "A. M. Turing")]:
    got = name_of(new.get_user(conn, uid))
    assert got == want, f"the new build shows {got!r} for user {uid}; want {want!r}"
    got = old.get_user(conn, uid)["display_name"]
    assert got == want, f"the previous build shows {got!r} for user {uid}; want {want!r}"
"""

_check.run(os.path.abspath(sys.argv[1]), "profiles-contract", CHECK)
