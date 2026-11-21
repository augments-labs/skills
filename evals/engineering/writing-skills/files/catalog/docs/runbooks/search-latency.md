# Search latency

1. Check the query cache hit rate on the search dashboard. Below 60% usually
   means a deploy flushed it; it recovers in about 20 minutes.
2. Look for a hot shard (one node above 80% CPU). Move it with
   `catalogctl shard move`.
3. Do not reindex during a latency incident: a build eats cluster CPU.
