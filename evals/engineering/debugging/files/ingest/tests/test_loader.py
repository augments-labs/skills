import os
import tempfile
import unittest

from ingest import load_file

ROW_A = '{"id": "a", "name": "Kim Park", "city": "Busan", "amount": 1, "ts": "2026-02-28T01:00:00+09:00"}'
ROW_B = '{"id": "b", "name": "Lee Tan", "city": "Ipoh", "amount": 2, "ts": "2026-02-28T02:00:00+08:00"}'


class LoadFileTests(unittest.TestCase):
    def write(self, text):
        fd, path = tempfile.mkstemp(suffix=".jsonl")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        self.addCleanup(os.remove, path)
        return path

    def test_loads_records_in_order(self):
        path = self.write(ROW_A + "\n" + ROW_B + "\n")
        self.assertEqual([r.id for r in load_file(path)], ["a", "b"])

    def test_skips_blank_lines(self):
        path = self.write("\n" + ROW_A + "\n\n")
        self.assertEqual(len(load_file(path)), 1)

    def test_bundled_batch_imports(self):
        here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        records = load_file(os.path.join(here, "fixtures", "batch_ok.jsonl"))
        self.assertEqual(len(records), 12)


if __name__ == "__main__":
    unittest.main()
