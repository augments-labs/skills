import json
import os
import threading
from pathlib import Path

from .entry import Entry

JOURNAL_NAME = "journal.wal"


class Ledger:
    """An append-only ledger kept as JSON lines.

    Amounts are integer cents. Each append goes to the journal before the data
    file; ``checkpoint`` empties the journal once the data file is safe.
    """

    def __init__(self, path):
        self.path = Path(path)
        self.journal_path = self.path.parent / JOURNAL_NAME
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._next_id = max((e.id for e in self.entries()), default=0) + 1

    def append(self, account, amount, memo=""):
        with self._lock:
            entry = Entry(self._next_id, account, int(amount), memo)
            line = json.dumps(entry.to_dict(), sort_keys=True) + "\n"
            with open(self.journal_path, "a", encoding="utf-8") as journal:
                journal.write(line)
                journal.flush()
                os.fsync(journal.fileno())
            with open(self.path, "a", encoding="utf-8") as data:
                data.write(line)
            self._next_id += 1
            return entry

    def entries(self):
        return [Entry.from_dict(json.loads(line)) for line in _read_lines(self.path)]

    def balance(self, account):
        return sum(e.amount for e in self.entries() if e.account == account)

    def recover(self):
        """Append journaled entries that never reached the data file."""
        with self._lock:
            known = {e.id for e in self.entries()}
            missing = [line for line in _read_lines(self.journal_path)
                       if json.loads(line)["id"] not in known]
            if missing:
                with open(self.path, "a", encoding="utf-8") as data:
                    data.writelines(line + "\n" for line in missing)
            self._next_id = max((e.id for e in self.entries()), default=0) + 1
            return len(missing)

    def checkpoint(self):
        with self._lock:
            open(self.journal_path, "w", encoding="utf-8").close()


def _read_lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            return [line.rstrip("\n") for line in f if line.strip()]
    except FileNotFoundError:
        return []
