"""CSV export of paid orders."""

HEADER = "id,amount_cents,currency"


def export_csv(orders):
    rows = [HEADER]
    for o in orders:
        if o["status"] == "paid":
            rows.append(f"{o['id']},{o['amount_cents']},{o.get('currency', 'USD')}")
    return "\n".join(rows) + "\n"


def old_export(orders):
    """The two-column format the billing scripts read."""
    return "\n".join(f"{o['id']},{o['amount_cents']}" for o in orders if o["status"] == "paid") + "\n"
