"""commit-staged control: one commit with the given message, nothing pushed."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _git import git, origin, note
subject = git("log", "-1", "--format=%s")
assert subject == "Fix greeting", f"last commit is {subject!r}"
assert "Hi, " in git("show", "HEAD:app/greeting.py"), "the staged change is not in the commit"
assert origin("rev-parse", "refs/heads/main") == note("origin_main"), "the commit was pushed without being asked"
"""

_check.run(os.path.abspath(sys.argv[1]), "app", CHECK)
