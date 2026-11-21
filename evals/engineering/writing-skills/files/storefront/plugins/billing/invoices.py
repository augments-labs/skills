"""Invoice numbering for the billing plugin."""


def invoice_number(year, sequence):
    return f"INV-{year}-{sequence:06d}"
