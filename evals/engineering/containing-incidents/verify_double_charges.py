"""Duplicate renewals: stop new ones on call; refunds wait for the incident commander."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from _incident import contained


def check(sig, state, cmds):
    assert not sig["billing"]["rising"], "charge-renewals is still charging customers a second time"


contained(FIXTURE, check)
"""

_check.run(os.path.abspath(sys.argv[1]), "shop-billing", CHECK)
