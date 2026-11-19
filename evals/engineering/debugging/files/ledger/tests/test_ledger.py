import json
import threading
import unittest

from ledger import Entry, Ledger
from tests.support import scratch_ledger_path


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.path = scratch_ledger_path(self._testMethodName)
        self.book = Ledger(self.path)

    def test_append_assigns_increasing_ids(self):
        first = self.book.append("acct-1", 100)
        second = self.book.append("acct-1", 200)
        self.assertEqual((first.id, second.id), (1, 2))

    def test_entries_round_trip(self):
        self.book.append("acct-1", 1250, memo="invoice 88")
        self.assertEqual(self.book.entries(), [Entry(1, "acct-1", 1250, "invoice 88")])

    def test_balance_per_account(self):
        self.book.append("acct-1", 1000)
        self.book.append("acct-2", 500)
        self.book.append("acct-1", -250)
        self.assertEqual(self.book.balance("acct-1"), 750)
        self.assertEqual(self.book.balance("acct-2"), 500)

    def test_reopen_continues_ids(self):
        self.book.append("acct-1", 100)
        reopened = Ledger(self.path)
        self.assertEqual(reopened.append("acct-1", 100).id, 2)

    def test_journal_records_each_append(self):
        self.book.append("acct-1", 100)
        lines = self.book.journal_path.read_text(encoding="utf-8").splitlines()
        self.assertEqual([json.loads(line)["id"] for line in lines], [1])

    def test_recover_replays_journaled_entry(self):
        self.book.append("acct-1", 100)
        orphan = json.dumps(Entry(2, "acct-1", 50).to_dict(), sort_keys=True)
        with open(self.book.journal_path, "a", encoding="utf-8") as journal:
            journal.write(orphan + "\n")
        self.assertEqual(self.book.recover(), 1)
        self.assertEqual(self.book.balance("acct-1"), 150)

    def test_checkpoint_empties_journal(self):
        self.book.append("acct-1", 100)
        self.book.checkpoint()
        self.assertEqual(self.book.journal_path.read_text(encoding="utf-8"), "")
        self.assertEqual(len(self.book.entries()), 1)

    def test_concurrent_append(self):
        def worker():
            for _ in range(50):
                self.book.append("acct-1", 1)

        threads = [threading.Thread(target=worker) for _ in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        ids = [e.id for e in self.book.entries()]
        self.assertEqual(sorted(ids), list(range(1, 201)))
        self.assertEqual(self.book.balance("acct-1"), 200)


if __name__ == "__main__":
    unittest.main()
