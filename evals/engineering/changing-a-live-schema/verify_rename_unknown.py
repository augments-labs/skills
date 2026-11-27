"""rename-unknown-user control."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _live import *
conn = production_db(FIXTURE)
from app import users
try:
    users.rename_user(conn, 999, "Nobody")
except LookupError:
    pass
else:
    raise AssertionError("rename_user(999) did not raise LookupError")
uid = users.create_user(conn, "ada@example.com", "Ada Lovelace")
users.rename_user(conn, uid, "Ada King")
assert users.get_user(conn, uid)["fullname"] == "Ada King"
"""

_check.run(os.path.abspath(sys.argv[1]), "profiles", CHECK)
