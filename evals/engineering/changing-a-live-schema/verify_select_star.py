"""select-star: replicas that unpack SELECT * keep working during the rollout."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import sqlite3
from _live import *
applied_migrations_unchanged(FIXTURE)
old = previous_build(FIXTURE)
conn = production_db(FIXTURE)
ada = old.create_user(conn, "ada@example.com", "Ada Lovelace")
run_migrate(conn)
still_serves("read a user", lambda: old.get_user(conn, ada))
grace = still_serves("create a user", lambda: old.create_user(conn, "grace@example.com", "Grace Hopper"))
still_serves("read a user", lambda: old.get_user(conn, grace))

from app import users as new
alan = new.create_user(conn, "alan@example.com", "Alan Turing")
assert name_of(new.get_user(conn, ada)) == "Ada Lovelace", "the new build misreads an existing user"
delivered = False
if hasattr(new, "record_login"):
    new.record_login(conn, alan)
    delivered = (new.get_user(conn, alan) or {}).get("last_login_at") is not None
if not delivered:
    # A first deploy that only stops unpacking SELECT * is a safe step: the new
    # build must then read users correctly once the next deploy adds a column.
    nxt = production_db(FIXTURE)
    run_migrate(nxt)
    kay = new.create_user(nxt, "kay@example.com", "Kay Nygaard")
    nxt.execute("ALTER TABLE users ADD COLUMN next_deploy_column TEXT")
    nxt.commit()
    try:
        kay_name = name_of(new.get_user(nxt, kay))
    except (sqlite3.Error, ValueError, TypeError, KeyError) as e:
        raise AssertionError(
            "the new build neither records last_login_at nor survives a column added "
            f"to users: {type(e).__name__}: {e}")
    assert kay_name == "Kay Nygaard", (
        "the new build neither records last_login_at nor reads users correctly once a "
        f"column is added: got {kay_name!r}")
"""

_check.run(os.path.abspath(sys.argv[1]), "profiles-selectstar", CHECK)
