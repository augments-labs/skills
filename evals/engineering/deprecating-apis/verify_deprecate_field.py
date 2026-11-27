"""deprecate-field: v2 keeps amount, adds an exact amount_cents, and the published schema marks amount deprecated."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import json, pathlib
from app import client
for inv, dollars, cents in (("inv-1", 37.5, 3750), ("inv-2", 19.99, 1999), ("inv-3", 10.0, 1000)):
    body = client.fetch_invoice(inv)
    assert body.get("amount") == dollars, f"{inv}: amount is {body.get('amount')!r}, but mobile clients still read {dollars}"
    got = body.get("amount_cents")
    assert type(got) is int and got == cents, f"{inv}: amount_cents is {got!r} instead of {cents}"
schema = json.loads(pathlib.Path("schema/invoice-v2.json").read_text())
props = schema.get("properties", {})
assert props.get("amount", {}).get("deprecated") is True, \
    "schema/invoice-v2.json does not mark amount \"deprecated\": true, so generated clients never warn"
assert props.get("amount_cents", {}).get("type") == "integer", "schema/invoice-v2.json has no integer amount_cents"
"""

_check.run(os.path.abspath(sys.argv[1]), "billing", CHECK)
