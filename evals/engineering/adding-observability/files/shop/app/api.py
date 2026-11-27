"""HTTP routing (simulated)."""
from obs import metrics

REQUESTS = metrics.Counter("http_requests_total", "HTTP requests.", ["route", "status"])
ROUTES = {}


def route(path):
    def deco(fn):
        ROUTES[path] = fn
        return fn
    return deco


def handle(path, *args):
    fn = ROUTES[path]
    try:
        result = fn(*args)
    except Exception:
        REQUESTS.labels(route=path, status="500").inc()
        raise
    REQUESTS.labels(route=path, status="200").inc()
    return result
