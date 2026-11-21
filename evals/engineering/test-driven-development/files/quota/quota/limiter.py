class FixedLimiter:
    """At most `limit` calls per key in each calendar window of `window` seconds."""

    def __init__(self, limit, window):
        if limit < 1 or window <= 0:
            raise ValueError("limit must be >= 1 and window > 0")
        self.limit = limit
        self.window = window
        self._counts = {}

    def allow(self, key, now):
        bucket = (key, int(now // self.window))
        used = self._counts.get(bucket, 0)
        if used >= self.limit:
            return False
        self._counts[bucket] = used + 1
        return True
