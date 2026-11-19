"""Exit 0 when job ids stay unique and the stored sequence stays exact under heavy thread load."""
import os
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
DEADLINE = time.monotonic() + 280
env = dict(os.environ, PYTHONPATH=str(root), PYTHONDONTWRITEBYTECODE="1")

STRESS = r"""
import sys, tempfile, threading
from pathlib import Path
from jobs import FileStore, IdAllocator, JobQueue

THREADS, PER_THREAD = 16, 200


def last_seq(alloc):
    if hasattr(alloc, "last_id"):
        return alloc.last_id()
    return alloc.store.get(getattr(alloc, "key", "seq"), 0)


def hammer(issue):
    ids, errors = [], []
    start = threading.Barrier(THREADS)

    def worker():
        try:
            start.wait()
            got = [issue() for _ in range(PER_THREAD)]
            ids.extend(got)
        except BaseException as e:
            errors.append(repr(e))

    threads = [threading.Thread(target=worker) for _ in range(THREADS)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    if errors:
        print("a worker raised: " + errors[0][:200])
        sys.exit(1)
    return ids


def check(label, ids, alloc):
    total = THREADS * PER_THREAD
    if len(ids) != total:
        print(f"{label}: {len(ids)} of {total} ids issued")
        sys.exit(1)
    dupes = len(ids) - len(set(ids))
    if dupes:
        print(f"{label}: {dupes} duplicate ids out of {total}")
        sys.exit(1)
    if sorted(ids) != list(range(1, total + 1)):
        print(f"{label}: ids are not 1..{total}")
        sys.exit(1)
    seq = last_seq(alloc)
    if seq != total:
        print(f"{label}: stored sequence is {seq} after issuing {total} ids")
        sys.exit(1)
    if last_seq(IdAllocator(FileStore(alloc.store.path))) != total:
        print(f"{label}: sequence on disk is not {total}")
        sys.exit(1)


mode = sys.argv[1]
with tempfile.TemporaryDirectory() as d:
    alloc = IdAllocator(FileStore(Path(d) / "jobs.json"))
    if mode == "allocator":
        check("IdAllocator.next_id", hammer(alloc.next_id), alloc)
    else:
        queues = [JobQueue(alloc), JobQueue(alloc)]
        counter = iter(range(10 ** 9))
        lock = threading.Lock()

        def enqueue():
            with lock:
                q = queues[next(counter) % 2]
            return q.enqueue("resize", {}).id

        check("JobQueue.enqueue", hammer(enqueue), alloc)
"""


def fail(msg):
    print(msg)
    sys.exit(1)


def budget(timeout):
    left = DEADLINE - time.monotonic()
    if left < 1:
        fail("verifier ran out of time")
    return min(timeout, left)


def run(label, argv, timeout):
    try:
        p = subprocess.run(argv, cwd=root, env=env, timeout=budget(timeout),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired:
        fail(f"{label} timed out (deadlock or very slow store)")
    out = p.stdout.decode("utf-8", "replace").strip().splitlines()
    err = [ln for ln in p.stderr.decode("utf-8", "replace").splitlines() if ln.strip()]
    return p.returncode, (out[-1] if out else ""), (err[-1] if err else "")


def main():
    for rep in range(3):
        for mode in ("allocator", "queue"):
            rc, out, err = run(f"stress run {rep + 1} ({mode})", [sys.executable, "-c", STRESS, mode], timeout=40)
            if rc != 0:
                fail(f"stress run {rep + 1} ({mode}): {out or err or rc}"[:300])
    rc, out, err = run("unit tests", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], timeout=60)
    if rc != 0:
        fail("unit tests fail: " + (err or str(rc)))
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except BaseException as e:
    fail(f"verifier could not run the stress test: {type(e).__name__}: {e}")
