# jobs

A small job queue. Job ids come from `IdAllocator`, which keeps the last id
in a JSON file through `FileStore`, so ids keep increasing across restarts.
`submit_all` enqueues a batch of jobs from a pool of worker threads.

```python
from jobs import FileStore, IdAllocator, JobQueue

queue = JobQueue(IdAllocator(FileStore("state/jobs.json")))
job = queue.enqueue("resize", {"image": "cat.png"})
```

## Tests

```bash
python3 -m unittest discover -s tests -t .
```
