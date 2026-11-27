"""Account activity feed."""


def recent_events_for_account(conn, account_id, limit=50):
    """Newest events first, for the account activity page."""
    rows = conn.execute(
        "SELECT id, kind, payload, created_at FROM events"
        " WHERE account_id = %s ORDER BY created_at DESC LIMIT %s",
        (account_id, limit),
    ).fetchall()
    return [dict(zip(("id", "kind", "payload", "created_at"), r)) for r in rows]


def record_event(conn, account_id, kind, payload):
    with conn.transaction():
        conn.execute(
            "INSERT INTO events (account_id, kind, payload) VALUES (%s, %s, %s)",
            (account_id, kind, payload),
        )
