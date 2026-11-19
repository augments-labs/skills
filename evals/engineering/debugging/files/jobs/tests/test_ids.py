import tempfile
import unittest
from pathlib import Path

from jobs import FileStore, IdAllocator, JobQueue, submit_all


class IdAllocatorTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.store = FileStore(Path(tmp.name) / "jobs.json")

    def test_ids_start_at_one_and_increase(self):
        ids = IdAllocator(self.store)
        self.assertEqual([ids.next_id() for _ in range(3)], [1, 2, 3])

    def test_ids_continue_after_restart(self):
        IdAllocator(self.store).next_id()
        self.assertEqual(IdAllocator(self.store).next_id(), 2)

    def test_unique_ids_under_load(self):
        queue = JobQueue(IdAllocator(self.store))
        payloads = [{"n": n} for n in range(100)]
        jobs = submit_all(queue, "resize", payloads, workers=4, interval=0.001)
        ids = [job.id for job in jobs]
        if len(set(ids)) != len(ids):
            self.fail("duplicate job ids")
        self.assertEqual(len(queue), 100)


if __name__ == "__main__":
    unittest.main()
