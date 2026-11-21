def check_request(limiter, api_key, clock):
    return 200 if limiter.allow(api_key, clock.now()) else 429
