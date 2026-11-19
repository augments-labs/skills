from .parse import parse_line


def load_file(path):
    """Read every record in a batch file, in order."""
    records = []
    with open(path, "rb") as f:
        for raw in f:
            raw = raw.strip()
            if raw:
                records.append(parse_line(raw))
    return records
