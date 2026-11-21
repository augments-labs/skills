import unittest

from syncer.engine import Syncer
from syncer.errors import DuplicateSource, UnknownSource
from syncer.sources import StaticSource
from syncer.store import MemoryStore


class SyncerTest(unittest.TestCase):
    def setUp(self):
        self.store = MemoryStore()
        self.syncer = Syncer(self.store)
        self.syncer.add_source(StaticSource("a", [1, 2]))
        self.syncer.add_source(StaticSource("b", [3]))

    def test_run_stores_every_source(self):
        self.syncer.run()
        self.assertEqual(self.store.data, {"a": [1, 2], "b": [3]})

    def test_progress(self):
        seen = []
        self.syncer.run(progress=lambda name, done, total: seen.append((name, done, total)))
        self.assertEqual(seen, [("a", 1, 2), ("b", 2, 2)])

    def test_duplicate_source(self):
        with self.assertRaises(DuplicateSource):
            self.syncer.add_source(StaticSource("a", []))

    def test_remove_unknown(self):
        with self.assertRaises(UnknownSource):
            self.syncer.remove_source("zzz")

    def test_rename(self):
        self.syncer.rename_source("a", "alpha")
        self.assertEqual(self.syncer.list_sources(), ["b", "alpha"])

    def test_interval_minimum(self):
        with self.assertRaises(ValueError):
            self.syncer.set_interval(5)


if __name__ == "__main__":
    unittest.main()
