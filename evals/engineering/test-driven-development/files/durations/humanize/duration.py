def describe(seconds):
    """Describe an elapsed time for display, e.g. "2 hours and 5 minutes"."""
    if seconds is None:
        return "-"
    if seconds < 0:
        raise ValueError(f"elapsed time cannot be negative: {seconds}")
    if seconds < 1:
        return "just now"
    total = round(seconds)
    parts = []
    days = total // 86400
    rest = total - days * 86400
    hours = rest // 3600
    rest = rest - hours * 3600
    minutes = rest // 60
    secs = rest - minutes * 60
    for amount, unit in ((days, "day"), (hours, "hour"), (minutes, "minute"), (secs, "second")):
        if amount == 0:
            continue
        if amount == 1:
            parts.append(f"1 {unit}")
        else:
            parts.append(f"{amount} {unit}s")
        if len(parts) == 2:
            break
    if len(parts) == 1:
        return parts[0]
    return parts[0] + " and " + parts[1]
