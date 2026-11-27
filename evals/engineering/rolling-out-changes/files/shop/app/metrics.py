"""Metrics. In production emit() feeds the metrics agent; here it records to EVENTS."""
EVENTS = []


def emit(name, value=1, **labels):
    EVENTS.append((name, value, dict(labels)))
