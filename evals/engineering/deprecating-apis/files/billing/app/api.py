from app import metrics, pricing, store
from app.http import Response, route


def _client(headers):
    return headers.get("X-Client-Id", "unknown")


@route("GET", "/v1/invoices/<invoice_id>")
def get_invoice_v1(headers, invoice_id):
    inv = store.get(invoice_id)
    return Response(200, {}, {
        "id": inv["id"],
        "customer": inv["customer"],
        "amount": pricing.legacy_total(inv["lines"]),
        "status": inv["status"],
    })


@route("GET", "/v2/invoices/<invoice_id>")
def get_invoice_v2(headers, invoice_id):
    inv = store.get(invoice_id)
    return Response(200, {}, {
        "id": inv["id"],
        "customer": inv["customer"],
        "amount": pricing.legacy_total(inv["lines"]),
        "currency": "USD",
        "status": inv["status"],
    })


@route("GET", "/v1/total/<invoice_id>")
def get_total_v1(headers, invoice_id):
    # Deprecated: callers moved to /v2/invoices. Counted so we know when it is unused.
    metrics.emit("deprecated.call", api="GET /v1/total", client=_client(headers))
    inv = store.get(invoice_id)
    return Response(200, {}, {"total": pricing.legacy_total(inv["lines"])})
