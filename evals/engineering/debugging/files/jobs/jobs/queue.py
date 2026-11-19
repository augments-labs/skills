from collections import deque
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Job:
    id: int
    kind: str
    payload: dict = field(default_factory=dict)


class JobQueue:
    def __init__(self, allocator):
        self.allocator = allocator
        self._pending = deque()

    def enqueue(self, kind, payload=None):
        job = Job(self.allocator.next_id(), kind, dict(payload or {}))
        self._pending.append(job)
        return job

    def drain(self):
        jobs = []
        while self._pending:
            jobs.append(self._pending.popleft())
        return jobs

    def __len__(self):
        return len(self._pending)
