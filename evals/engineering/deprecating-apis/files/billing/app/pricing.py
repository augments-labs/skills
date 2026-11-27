def total_cents(lines):
    return sum(line["qty"] * line["unit_cents"] for line in lines)


def legacy_total(lines):
    """Deprecated: use total_cents. Returns the total in dollars."""
    return round(total_cents(lines) / 100, 2)
