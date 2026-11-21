"""reject-empty-email control."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _live import *
conn = production_db(FIXTURE)
from app import users
for bad in ("", "   "):
    try:
        users.create_user(conn, bad, "Nobody")
    except ValueError:
        pass
    else:
        raise AssertionError(f"create_user accepted email {bad!r}")
uid = users.create_user(conn, "ada@example.com", "Ada Lovelace")
assert users.get_user(conn, uid)["email"] == "ada@example.com"
"""

_check.run(os.path.abspath(sys.argv[1]), "profiles", CHECK)
