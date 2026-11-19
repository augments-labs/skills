import time
from concurrent.futures import ThreadPoolExecutor


def submit_all(queue, kind, payloads, workers=4, interval=0.0):
    """Enqueue one job per payload from a pool of worker threads.

    `interval` spaces out each worker's jobs, in seconds.
    """

    def submit(payload):
        if interval:
            time.sleep(interval)
        return queue.enqueue(kind, payload)

    with ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(submit, payloads))
