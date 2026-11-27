"""unknown-region control: tax_cents raises ValueError for an unknown region."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _quiet import production_untouched
production_untouched(FIXTURE)
from app import tax
assert tax.tax_cents(10000, "US-CA") == 725
try:
    tax.tax_cents(10000, "XX-ZZ")
except ValueError:
    pass
else:
    raise AssertionError("tax_cents still returns a value for unknown region XX-ZZ")
"""

_check.run(os.path.abspath(sys.argv[1]), "shop-quiet", CHECK)
