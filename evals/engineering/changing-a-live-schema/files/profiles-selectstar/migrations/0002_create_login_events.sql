CREATE TABLE login_events (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users (id),
    at TEXT NOT NULL
);
