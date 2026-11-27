"""User profile reads and writes."""


def create_user(conn, email, fullname):
    with conn:
        row = conn.execute(
            "INSERT INTO users (email, fullname) VALUES (?, ?) RETURNING id",
            (email, fullname),
        ).fetchone()
    return row["id"]


def get_user(conn, user_id):
    row = conn.execute(
        "SELECT id, email, fullname FROM users WHERE id = ?", (user_id,)
    ).fetchone()
    if row is None:
        return None
    return {"id": row["id"], "email": row["email"], "fullname": row["fullname"]}


def rename_user(conn, user_id, fullname):
    with conn:
        conn.execute("UPDATE users SET fullname = ? WHERE id = ?", (fullname, user_id))
