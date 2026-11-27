"""The recommendations vendor. In production fetch_recs() is an HTTP call."""
CALLS = []


def fetch_recs(customer_id, timeout=2.0):
    CALLS.append(customer_id)
    return ["mug", "socks"]
