"""Client other internal teams import to read invoices."""
from app import api, http  # noqa: F401  (registers the routes)


def get_invoice(invoice_id):
    """Return an invoice in the v1 shape."""
    return http.handle("GET", f"/v1/invoices/{invoice_id}", {"X-Client-Id": "python-client"}).body


def fetch_invoice(invoice_id):
    """Return an invoice in the v2 shape."""
    return http.handle("GET", f"/v2/invoices/{invoice_id}", {"X-Client-Id": "python-client"}).body
