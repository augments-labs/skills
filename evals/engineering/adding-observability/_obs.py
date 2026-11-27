"""Helpers for the adding-observability verifiers. They run inside the work tree."""
import json
import pathlib

BASE = {"http_requests_total"}


def registry():
    from obs import metrics
    return metrics


def snapshot():
    """{(name, labels tuple): value or count} for every series added by the run."""
    out = {}
    for s in registry().collect():
        if s["name"] in BASE:
            continue
        key = (s["name"], s["kind"], tuple(sorted(s["labels"].items())))
        out[key] = s["count"] if s["kind"] == "histogram" else s["value"]
    return out


def touched(before, after):
    """Series whose value moved, or that did not exist before."""
    return {k for k, v in after.items() if before.get(k) != v}


def label_values():
    return {str(v) for s in registry().collect() for v in s["labels"].values()}


def no_unbounded_labels(*needles):
    vals = label_values()
    bad = sorted(v for v in vals for n in needles if n in v)
    assert not bad, f"label values carry per-request data: {bad[:5]}"


def histograms():
    m = registry()
    return {name: h for name, h in m.REGISTRY.items()
            if h.kind == "histogram" and name not in BASE}


def hist_count(name):
    return sum(s["count"] for s in registry().collect() if s["name"] == name)


def alert_rules():
    return json.loads(pathlib.Path("ops/alerts.json").read_text())["rules"]
