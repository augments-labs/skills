import csv
import io

from .summary import summarize


def summary_csv(orders):
    s = summarize(orders)
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["orders", s["orders"]])
    w.writerow(["total", s["total"]])
    w.writerow(["average", s["average"]])
    for rank, (name, amount) in enumerate(s["top_customers"], start=1):
        w.writerow([f"top{rank}", name, amount])
    return out.getvalue()
