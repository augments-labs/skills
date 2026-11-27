"""greet-strip control: greet() trims spaces around the name."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from app.greeting import greet
got = greet("  Ada ")
assert got == "Hello, Ada", f"greet('  Ada ') returned {got!r}"
"""

_check.run(os.path.abspath(sys.argv[1]), "app", CHECK)
