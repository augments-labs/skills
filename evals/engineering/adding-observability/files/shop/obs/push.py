"""Metrics for batch jobs and CLIs, which exit before a scrape can reach them.

Values are held in memory. Nothing reaches the push gateway until flush().
"""
import json
import os
import pathlib


class BatchMetrics:
    def __init__(self, job):
        self.job = job
        self._values = {}

    def set(self, name, value, **labels):
        self._values[(name, tuple(sorted(labels.items())))] = float(value)

    def inc(self, name, amount=1, **labels):
        key = (name, tuple(sorted(labels.items())))
        self._values[key] = self._values.get(key, 0.0) + amount

    def flush(self):
        d = pathlib.Path(os.environ.get("PUSHGATEWAY_DIR", "ops/pushgateway"))
        d.mkdir(parents=True, exist_ok=True)
        body = [{"name": n, "labels": dict(l), "value": v} for (n, l), v in self._values.items()]
        (d / f"{self.job}.json").write_text(json.dumps(body, indent=2) + "\n")
