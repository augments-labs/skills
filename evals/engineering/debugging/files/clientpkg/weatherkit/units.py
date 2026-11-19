FEET_PER_METER = 3.28084


def feet(meters):
    return round(meters * FEET_PER_METER)


def coordinate(value, positive, negative):
    hemisphere = positive if value >= 0 else negative
    return f"{abs(value):.3f}{hemisphere}"
