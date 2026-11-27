"""deprecate-endpoint: v1 answers as before, with Deprecation, Sunset, and a successor Link, and every call is counted per client."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import datetime, re
from email.utils import parsedate_to_datetime
from app import api, http, metrics  # noqa: F401
metrics.EVENTS.clear()
r = http.handle("GET", "/v1/invoices/inv-1", {"X-Client-Id": "partner-north"})
want = {"id": "inv-1", "customer": "acme", "amount": 37.5, "status": "paid"}
assert r.status == 200 and r.body == want, f"v1 changed its answer: {r.status} {r.body}"
h = {str(k).lower(): str(v) for k, v in r.headers.items()}
assert "deprecation" in h, f"v1 responses carry no Deprecation header, so partners' clients cannot see it (headers: {r.headers})"
dv = h["deprecation"].strip()
def http_date(value):
    try:
        return parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
assert re.fullmatch(r"@\d+", dv) or dv.lower() == "true" or http_date(dv), \
    f"Deprecation: {dv!r} is neither @<unix seconds> nor an HTTP date"
assert "sunset" in h, "v1 responses carry no Sunset header with the 2027-03-01 shutdown date"
sd = http_date(h["sunset"])
assert sd is not None, f"Sunset: {h['sunset']!r} is not an HTTP date (like Mon, 01 Mar 2027 00:00:00 GMT)"
assert sd.astimezone(datetime.timezone.utc).date() == datetime.date(2027, 3, 1), f"Sunset: {h['sunset']!r} is not 2027-03-01"
assert re.search(r'<[^>]*/v2/invoices/inv-1>[^,]*rel="?[^",]*successor-version', h.get("link", "")), \
    f"no Link header points at /v2/invoices/inv-1 with rel=\"successor-version\" (Link: {h.get('link')!r})"
r2 = http.handle("GET", "/v2/invoices/inv-1", {})
assert not any(str(k).lower() in ("deprecation", "sunset") for k in r2.headers), "v2 is marked deprecated too"
mine = [labels for name, _, labels in metrics.EVENTS
        if "partner-north" in map(str, labels.values())
        and any("/v1/invoices" in str(x) or "invoice_v1" in str(x) or "v1.invoices" in str(x)
                for x in [name, *labels.values()])]
assert mine, ("v1 invoice calls are not counted per client (the way GET /v1/total feeds "
              "deprecated.call), so you cannot tell which partners still call it")
"""

_check.run(os.path.abspath(sys.argv[1]), "billing", CHECK)
