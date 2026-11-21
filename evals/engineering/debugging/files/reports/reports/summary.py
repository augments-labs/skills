from collections import defaultdict
from decimal import Decimal

HEADER = ("Customer", "Region", "Orders", "Net")


def summarize(orders):
    """Rows of (customer, region, order count, net amount), sorted."""
    groups = defaultdict(lambda: [0, Decimal("0")])
    for order in orders:
        group = groups[(order.customer, order.region)]
        group[0] += 1
        group[1] += order.amount
    return sorted((customer, region, count, net) for (customer, region), (count, net) in groups.items())


def _line(customer, region, count, net):
    if isinstance(net, Decimal):
        net = f"{net:,.2f}"
    return f"{customer:<10}{region:<8}{count:>7}{net:>12}"


def render(orders):
    rows = summarize(orders)
    lines = [_line(*HEADER)]
    lines += [_line(*row) for row in rows]
    lines.append(_line("TOTAL", "", sum(r[2] for r in rows), sum((r[3] for r in rows), Decimal("0"))))
    return "\n".join(lines) + "\n"
