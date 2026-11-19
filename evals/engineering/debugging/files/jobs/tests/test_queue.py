import tempfile
import unittest
from pathlib import Path

from jobs import FileStore, IdAllocator, JobQueue


class JobQueueTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.queue = JobQueue(IdAllocator(FileStore(Path(tmp.name) / "jobs.json")))

    def test_enqueue_returns_job(self):
        job = self.queue.enqueue("resize", {"image": "cat.png"})
        self.assertEqual((job.id, job.kind, job.payload), (1, "resize", {"image": "cat.png"}))

    def test_drain_in_order(self):
        for kind in ("a", "b", "c"):
            self.queue.enqueue(kind)
        self.assertEqual([j.kind for j in self.queue.drain()], ["a", "b", "c"])
        self.assertEqual(len(self.queue), 0)


if __name__ == "__main__":
    unittest.main()
