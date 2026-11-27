from app import vendor


def recommendations_for(customer_id):
    return vendor.fetch_recs(customer_id, timeout=2.0)
