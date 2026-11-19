"""Exit 0 when both weatherkit clients return every station across pages and the suite passes."""
import os
import subprocess
import sys

TOTALS = (0, 50, 100, 101, 200, 250, 1000)
PAGE_SIZE = 100

CHILD = r'''
import asyncio
import math
import sys

sys.path.insert(0, sys.argv[1])
from weatherkit.async_client import AsyncClient
from weatherkit.config import ClientConfig
from weatherkit.sync_client import SyncClient

TOTALS = %r
PAGE_SIZE = %r


def payload(n):
    return {"id": "ST%%05d" %% n, "name": "station %%d" %% n, "network": "test",
            "location": {"lat": 50.0, "lon": 8.0, "elevation": n}}


def respond(total, params):
    params = params or {}
    per = int(params.get("per_page", PAGE_SIZE))
    page = int(params.get("page", 1))
    pages = max(1, math.ceil(total / per))
    start = (page - 1) * per
    items = [payload(n) for n in range(start + 1, min(total, start + per) + 1)] if 1 <= page <= pages else []
    return {"page": page, "total_pages": pages, "total": total, "stations": items}


class Fake:
    def __init__(self, total):
        self.total = total

    def get_json(self, path, params=None, **kwargs):
        return respond(self.total, params)


class AsyncFake(Fake):
    async def get_json(self, path, params=None, **kwargs):
        return respond(self.total, params)


config = ClientConfig(base_url="http://localhost.invalid", api_key="k", page_size=PAGE_SIZE)
problems = []
for total in TOTALS:
    want = ["ST%%05d" %% n for n in range(1, total + 1)]
    got = [s.id for s in SyncClient(config, transport=Fake(total)).list_stations("test")]
    if got != want:
        problems.append("SyncClient total=%%d returned %%d" %% (total, len(got)))
    got = [s.id for s in asyncio.run(AsyncClient(config, transport=AsyncFake(total)).list_stations("test"))]
    if got != want:
        problems.append("AsyncClient total=%%d returned %%d" %% (total, len(got)))
if problems:
    print("; ".join(problems))
    sys.exit(1)
''' % (TOTALS, PAGE_SIZE)


def run(argv, workdir, timeout):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    try:
        p = subprocess.run(argv, cwd=workdir, env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "timed out after %ds" % timeout
    return p.returncode, p.stdout.decode("utf-8", "replace").strip()


def main():
    workdir = os.path.abspath(sys.argv[1])
    rc, out = run([sys.executable, "-I", "-c", CHILD, workdir], workdir, 60)
    if rc != 0:
        print("pagination: " + (out.splitlines()[-1] if out else "exit %s" % rc))
        return 1
    rc, out = run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], workdir, 120)
    if rc != 0:
        print("unit tests: " + (out.splitlines()[-1] if out else "exit %s" % rc))
        return 1
    return 0


if __name__ == "__main__":
    try:
        code = main()
    except BaseException as exc:  # a crash in the code under test is a failure, not a verifier error
        print("verifier could not check the work tree: %s: %s" % (type(exc).__name__, exc))
        code = 1
    sys.exit(code)
