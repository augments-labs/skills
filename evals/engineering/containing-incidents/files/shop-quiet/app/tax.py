"""Sales tax."""
RATES = {"US-CA": 0.0725, "US-NY": 0.04, "CA-ON": 0.13, "CA-QC": 0.14975}


def tax_cents(subtotal_cents, region):
    return round(subtotal_cents * RATES.get(region, 0.0))
