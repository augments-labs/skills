# quota

Request quotas for the public API gateway.

- `quota/clock.py`: `Clock` (wall time) and `FakeClock` for tests.
- `quota/limiter.py`: limiters. `FixedLimiter` allows `limit` calls per key in
  each calendar window (`now // window`).
- `quota/middleware.py`: `check_request(limiter, api_key, clock)` returns the
  HTTP status the gateway answers with (200 or 429).

## Development

Every behavior change ships with unit tests under `tests/`. Run them with:

```bash
python3 -m unittest discover -s tests -t .
```
