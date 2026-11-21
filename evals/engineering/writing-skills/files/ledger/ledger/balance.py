"""Account balances."""


def balance(entries, account_id):
    return sum(e["amount_cents"] for e in entries if e["account_id"] == account_id)
