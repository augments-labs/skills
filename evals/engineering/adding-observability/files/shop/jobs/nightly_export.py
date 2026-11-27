"""Nightly export of paid orders for the warehouse.

Cron runs `python3 -m jobs.nightly_export [SOURCE]` at 02:00.
"""
import json
import pathlib
import sys


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    source = argv[0] if argv else "data/orders.json"
    orders = json.loads(pathlib.Path(source).read_text())
    rows = []
    for o in orders:
        if o["status"] == "paid":
            rows.append(f"{o['id']},{o['amount_cents']}")
    out = pathlib.Path("out")
    out.mkdir(exist_ok=True)
    (out / "export.csv").write_text("\n".join(rows) + "\n")
    print(f"exported {len(rows)} orders")
    return 0


if __name__ == "__main__":
    sys.exit(main())
