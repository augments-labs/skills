"""User profile reads and writes."""


def create_user(conn, email, display_name):
    # fullname is still written until the rename finishes (see README).
    with conn:
        row = conn.execute(
            "INSERT INTO users (email, fullname, display_name) VALUES (?, ?, ?) RETURNING id",
            (email, display_name, display_name),
        ).fetchone()
    return row["id"]


def get_user(conn, user_id):
    row = conn.execute(
        "SELECT id, email, display_name FROM users WHERE id = ?", (user_id,)
    ).fetchone()
    if row is None:
        return None
    return {"id": row["id"], "email": row["email"], "display_name": row["display_name"]}


def rename_user(conn, user_id, display_name):
    with conn:
        conn.execute(
            "UPDATE users SET fullname = ?, display_name = ? WHERE id = ?",
            (display_name, display_name, user_id),
        )
