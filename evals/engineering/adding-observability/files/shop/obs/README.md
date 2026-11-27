# Metrics

- **Services** use `obs.metrics` (`Counter`, `Gauge`, `Histogram`). The
  service exposes `obs.metrics.render()` on `/metrics`, and Prometheus
  scrapes it.
- **Batch jobs and CLIs** exit before a scrape can reach them, so they use
  `obs.push.BatchMetrics`. Values stay in memory until `flush()` sends them
  to the push gateway.
- **Alert rules** live in `ops/alerts.json` and use PromQL.

```python
from obs import metrics

REQUESTS = metrics.Counter("http_requests_total", "HTTP requests.", ["route", "status"])
REQUESTS.labels(route="/orders/{id}", status="200").inc()
```
