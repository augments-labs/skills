"""A small in-process metrics registry with Prometheus semantics.

A metric without labels starts at zero as soon as it is created. A labelled
metric has no series until `.labels(...)` is first called for a given set of
label values.
"""
import threading

DEFAULT_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
REGISTRY = {}
_lock = threading.Lock()


class _CounterValue:
    def __init__(self):
        self.value = 0.0

    def inc(self, amount=1):
        if amount < 0:
            raise ValueError("counters only go up")
        with _lock:
            self.value += amount

    def snapshot(self):
        return {"value": self.value}


class _GaugeValue(_CounterValue):
    def inc(self, amount=1):
        with _lock:
            self.value += amount

    def dec(self, amount=1):
        self.inc(-amount)

    def set(self, value):
        with _lock:
            self.value = float(value)


class _HistogramValue:
    def __init__(self, buckets):
        self.buckets = buckets
        self.counts = [0] * len(buckets)
        self.count = 0
        self.sum = 0.0

    def observe(self, value):
        with _lock:
            self.count += 1
            self.sum += value
            for i, le in enumerate(self.buckets):
                if value <= le:
                    self.counts[i] += 1

    def snapshot(self):
        return {"count": self.count, "sum": self.sum,
                "buckets": dict(zip(self.buckets, self.counts))}


class _Metric:
    kind = ""

    def __init__(self, name, documentation, labelnames=()):
        if name in REGISTRY:
            raise ValueError(f"metric {name} is already registered")
        self.name, self.documentation = name, documentation
        self.labelnames = tuple(labelnames)
        self._series = {}
        REGISTRY[name] = self
        if not self.labelnames:
            self.labels()

    def _new(self):
        raise NotImplementedError

    def labels(self, **values):
        if set(values) != set(self.labelnames):
            raise ValueError(f"{self.name} takes labels {self.labelnames}, got {tuple(values)}")
        key = tuple(str(values[k]) for k in self.labelnames)
        with _lock:
            if key not in self._series:
                self._series[key] = self._new()
            return self._series[key]

    def _only(self):
        if self.labelnames:
            raise ValueError(f"{self.name} has labels; call .labels(...) first")
        return self._series[()]

    def collect(self):
        return [(dict(zip(self.labelnames, k)), v.snapshot()) for k, v in self._series.items()]


class Counter(_Metric):
    kind = "counter"

    def _new(self):
        return _CounterValue()

    def inc(self, amount=1):
        self._only().inc(amount)


class Gauge(_Metric):
    kind = "gauge"

    def _new(self):
        return _GaugeValue()

    def set(self, value):
        self._only().set(value)

    def inc(self, amount=1):
        self._only().inc(amount)

    def dec(self, amount=1):
        self._only().dec(amount)


class Histogram(_Metric):
    kind = "histogram"

    def __init__(self, name, documentation, labelnames=(), buckets=DEFAULT_BUCKETS):
        self.buckets = tuple(sorted(float(b) for b in buckets))
        super().__init__(name, documentation, labelnames)

    def _new(self):
        return _HistogramValue(self.buckets)

    def observe(self, value):
        self._only().observe(value)


def collect():
    """Every series: dicts with name, kind, labels, and the value or histogram data."""
    out = []
    for m in list(REGISTRY.values()):
        for labels, snap in m.collect():
            out.append({"name": m.name, "kind": m.kind, "labels": labels, **snap})
    return out


def render():
    """The Prometheus text format."""
    lines = []
    for m in REGISTRY.values():
        lines.append(f"# HELP {m.name} {m.documentation}")
        lines.append(f"# TYPE {m.name} {m.kind}")
        for labels, snap in m.collect():
            lab = ",".join(f'{k}="{v}"' for k, v in labels.items())
            if m.kind == "histogram":
                for le, c in snap["buckets"].items():
                    sep = "," if lab else ""
                    lines.append(f'{m.name}_bucket{{{lab}{sep}le="{le}"}} {c}')
                lines.append(f"{m.name}_count{{{lab}}} {snap['count']}")
                lines.append(f"{m.name}_sum{{{lab}}} {snap['sum']}")
            else:
                lines.append(f"{m.name}{{{lab}}} {snap['value']}")
    return "\n".join(lines) + "\n"
