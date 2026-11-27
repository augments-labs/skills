"""Monthly reconciliation: the report finance imports into the ledger."""
from app import pricing, store
from jobs import config


def run():
    mode = config.load("reconcile")["pricing_mode"]
    compute = getattr(pricing, f"{mode}_total")
    rows = []
    for inv in sorted(store.INVOICES.values(), key=lambda i: i["id"]):
        rows.append(f"{inv['id']},{inv['customer']},{compute(inv['lines']):.2f}")
    return rows
