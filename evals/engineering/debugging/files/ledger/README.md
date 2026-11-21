# ledger

An append-only ledger of account entries, stored as JSON lines. Every append
is written to `journal.wal` in the same directory first, so `recover()` can
replay an entry that was journaled but never reached the data file.

```python
from ledger import Ledger

book = Ledger("data/main.jsonl")
book.append("acct-1", 1250, memo="invoice 88")
print(book.balance("acct-1"))
```

## Tests

```bash
bash test.sh
```

`test.sh` runs the unit tests in `tests/`, then removes the scratch ledgers
they leave in `.test-tmp/`. Cleanup errors are written to
`.test-logs/cleanup.log`.
