def station_payload(n, network="test"):
    return {
        "id": f"ST{n:05d}",
        "name": f"station {n}",
        "network": network,
        "location": {"lat": 50.0 + n / 1000, "lon": 8.0, "elevation": n},
    }


def page_payload(stations, page=1, total_pages=1):
    return {
        "page": page,
        "total_pages": total_pages,
        "total": len(stations),
        "stations": stations,
    }


class FakeTransport:
    def __init__(self, responses):
        self.responses = responses
        self.calls = []

    def get_json(self, path, params=None):
        self.calls.append((path, dict(params or {})))
        return self.responses[path]


class FakeAsyncTransport:
    def __init__(self, responses):
        self.responses = responses
        self.calls = []

    async def get_json(self, path, params=None):
        self.calls.append((path, dict(params or {})))
        return self.responses[path]
