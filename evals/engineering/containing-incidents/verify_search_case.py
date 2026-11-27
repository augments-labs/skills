"""search-case control: search ignores case."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _quiet import production_untouched
production_untouched(FIXTURE)
from app import search
assert search.search("Red Mug") == ["red mug"], f"search('Red Mug') returns {search.search('Red Mug')}"
assert search.search("MUG") == ["red mug", "blue mug"], search.search("MUG")
assert search.search("kettle") == ["tea kettle"]
"""

_check.run(os.path.abspath(sys.argv[1]), "shop-quiet", CHECK)
