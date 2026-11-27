INVOICES = {
    "inv-1": {"id": "inv-1", "customer": "acme", "status": "paid",
              "lines": [{"sku": "seat", "qty": 3, "unit_cents": 1250}]},
    "inv-2": {"id": "inv-2", "customer": "globex", "status": "open",
              "lines": [{"sku": "plan", "qty": 1, "unit_cents": 1999}]},
    "inv-3": {"id": "inv-3", "customer": "initech", "status": "open",
              "lines": [{"sku": "seat", "qty": 3, "unit_cents": 333},
                        {"sku": "addon", "qty": 1, "unit_cents": 1}]},
}


def get(invoice_id):
    return INVOICES.get(invoice_id)
