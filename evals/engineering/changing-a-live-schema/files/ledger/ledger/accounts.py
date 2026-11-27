"""Account lookups."""

COLUMNS = ("id", "name", "plan", "region", "created_at")


def get_account(conn, account_id):
    row = conn.execute(
        "SELECT id, name, plan, region, created_at FROM accounts WHERE id = %s",
        (account_id,),
    ).fetchone()
    return dict(zip(COLUMNS, row)) if row else None
