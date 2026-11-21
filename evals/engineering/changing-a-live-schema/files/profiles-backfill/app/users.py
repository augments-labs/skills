"""User profile reads and writes.

`fullname` is the user's legal name. `display_name` is the name shown in the
product; a user can pick one, and until they do it is NULL and the product
shows `fullname`.
"""


def create_user(conn, email, fullname):
    with conn:
        row = conn.execute(
            "INSERT INTO users (email, fullname) VALUES (?, ?) RETURNING id",
            (email, fullname),
        ).fetchone()
    return row["id"]


def get_user(conn, user_id):
    row = conn.execute(
        "SELECT id, email, fullname, display_name FROM users WHERE id = ?", (user_id,)
    ).fetchone()
    if row is None:
        return None
    return {
        "id": row["id"],
        "email": row["email"],
        "fullname": row["fullname"],
        "display_name": row["display_name"] if row["display_name"] is not None else row["fullname"],
    }


def rename_user(conn, user_id, fullname):
    with conn:
        conn.execute("UPDATE users SET fullname = ? WHERE id = ?", (fullname, user_id))


def set_display_name(conn, user_id, display_name):
    with conn:
        conn.execute("UPDATE users SET display_name = ? WHERE id = ?", (display_name, user_id))
