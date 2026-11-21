# accounts

User accounts for the member portal. `AccountService` registers, closes, and
looks up members; it is written against a user store, and production uses
`SqliteUserStore`.

```python
from accounts import AccountService, SqliteUserStore

service = AccountService(SqliteUserStore("members.db"))
service.register("ada@example.com", "Ada")
```

## Tests

```bash
python3 -m unittest discover -s tests -t .
```

`tests/test_store.py` covers the SQLite store; `tests/test_service.py` runs the
service against the in-memory store in `tests/fakes.py`.
