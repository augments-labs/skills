import tempfile
import unittest
from pathlib import Path

from jobs import FileStore


class FileStoreTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / "state.json"

    def test_missing_key_returns_default(self):
        self.assertEqual(FileStore(self.path).get("seq", 0), 0)

    def test_set_then_get(self):
        store = FileStore(self.path)
        store.set("seq", 7)
        self.assertEqual(store.get("seq"), 7)

    def test_values_persist_across_instances(self):
        FileStore(self.path).set("name", "nightly")
        self.assertEqual(FileStore(self.path).get("name"), "nightly")


if __name__ == "__main__":
    unittest.main()
