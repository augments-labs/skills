from decimal import ROUND_HALF_EVEN, Decimal

CENT = Decimal("0.01")


def summarize(orders, top=3):
    """Summarize a month of orders for finance.

    Returns {"orders": int, "total": str, "average": str, "top_customers": [[name, total], ...]}.
    """
    count = 0
    total = Decimal("0")
    per_customer = {}
    names = {}
    for order in orders:
        status = (order.get("status") or "").strip().lower()
        if status == "cancelled" or status == "void":
            continue
        amount = Decimal(str(order["amount"]).strip())
        if status == "refunded":
            amount = -amount
        else:
            if status != "paid":
                if status == "pending":
                    continue
                raise ValueError(f"order {order.get('id')}: unknown status {order.get('status')!r}")
        count += 1
        total += amount
        raw = (order.get("customer") or "").strip()
        key = raw.casefold()
        if key not in per_customer:
            per_customer[key] = Decimal("0")
            names[key] = raw if raw else "(no name)"
        per_customer[key] += amount
    if count:
        average = (total / count).quantize(CENT, rounding=ROUND_HALF_EVEN)
    else:
        average = Decimal("0").quantize(CENT)
    ranked = []
    for key in per_customer:
        placed = False
        for i, (other, _) in enumerate(ranked):
            if per_customer[key] > per_customer[other]:
                ranked.insert(i, (key, per_customer[key]))
                placed = True
                break
        if not placed:
            ranked.append((key, per_customer[key]))
    top_customers = []
    for key, amount in ranked[:top]:
        if amount <= 0:
            continue
        top_customers.append([names[key], str(amount.quantize(CENT, rounding=ROUND_HALF_EVEN))])
    return {
        "orders": count,
        "total": str(total.quantize(CENT, rounding=ROUND_HALF_EVEN)),
        "average": str(average),
        "top_customers": top_customers,
    }
