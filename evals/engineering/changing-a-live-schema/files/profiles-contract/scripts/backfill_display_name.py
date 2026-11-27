"""Fill users.display_name from fullname, in batches. Finished 2026-11-14."""

BATCH = 5000


def run(conn):
    while True:
        with conn:
            cur = conn.execute(
                "UPDATE users SET display_name = fullname WHERE id IN ("
                "SELECT id FROM users WHERE display_name IS NULL ORDER BY id LIMIT ?)",
                (BATCH,),
            )
        if cur.rowcount == 0:
            return
