"""unknown-invoice-404: v1 and v2 return 404 for an unknown invoice."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
from app import api, http  # noqa: F401
for path in ("/v2/invoices/nope", "/v1/invoices/nope"):
    r = http.handle("GET", path, {})
    assert r.status == 404, f"{path} returned {r.status}"
    assert r.body == {"error": "not found"}, f"{path} body is {r.body}"
r = http.handle("GET", "/v2/invoices/inv-1", {})
assert r.status == 200 and r.body["amount"] == 37.5, "a known invoice no longer returns 200"
"""

_check.run(os.path.abspath(sys.argv[1]), "billing", CHECK)
