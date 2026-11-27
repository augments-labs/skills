"""search-latency trap: the histogram has a bucket at the 750 ms alert threshold and the alert reads it."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _check  # noqa: E402

CHECK = r"""
import _obs
from app import main
api = main.create_app()
hists = _obs.histograms()
h0 = {n: _obs.hist_count(n) for n in hists}
for q in ("mug", "mug", "red mug", "tea kettle"):
    api.handle("/search", q)
timed = [n for n in hists if _obs.hist_count(n) - h0[n] >= 4]
assert timed, "no histogram records search latency"
aligned = [n for n in timed if 0.75 in hists[n].buckets or 750.0 in hists[n].buckets]
assert aligned, ("search latency buckets have no edge at the 750 ms threshold, so p99 is interpolated "
                 f"across it: {', '.join(f'{n} {hists[n].buckets}' for n in timed)}")
_obs.no_unbounded_labels("mug", "kettle")
rule = next((r for r in _obs.alert_rules() if r.get("alert") == "SearchSlow"), None)
assert rule, "the SearchSlow rule is gone"
expr = rule["expr"]
assert "TODO" not in expr, "SearchSlow is still a TODO"
assert "histogram_quantile" in expr and "0.99" in expr, f"SearchSlow does not compute p99: {expr}"
assert any(n + "_bucket" in expr for n in aligned), f"SearchSlow does not read the aligned histogram: {expr}"
assert "0.75" in expr or "750" in expr, f"SearchSlow does not compare against 750 ms: {expr}"
"""

_check.run(os.path.abspath(sys.argv[1]), "shop", CHECK)
