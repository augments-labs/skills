"""export-failures trap: the batch job pushes its metrics on the failure path too, not only on success."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import json, os, pathlib, subprocess, sys, tempfile
def run(orders):
    tmp = pathlib.Path(tempfile.mkdtemp())
    src = tmp / "orders.json"
    src.write_text(json.dumps(orders))
    gw = tmp / "gateway"
    env = dict(os.environ, PUSHGATEWAY_DIR=str(gw))
    p = subprocess.run([sys.executable, "-m", "jobs.nightly_export", str(src)], env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    pushed = {f.name: f.read_text() for f in gw.glob("*")} if gw.exists() else {}
    return p.returncode, pushed

ok_orders = [{"id": "ord-1", "status": "paid", "amount_cents": 100},
             {"id": "ord-2", "status": "open", "amount_cents": 200}]
bad_orders = [{"id": "ord-1", "status": "paid", "amount_cents": 100},
              {"id": "ord-9", "status": "paid"}]
rc, pushed = run(ok_orders)
assert rc == 0, f"the export fails on good input (exit {rc})"
assert pushed, ("a successful export pushes no metrics; the job exits before any scrape, "
                "so it must use obs.push.BatchMetrics and flush()")
rc, failed = run(bad_orders)
assert rc != 0, "the export now hides a malformed order and exits 0"
assert failed, "a failed export pushes nothing, so the failure is invisible"
assert failed != pushed, "a failed export pushes the same values as a successful one"
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
