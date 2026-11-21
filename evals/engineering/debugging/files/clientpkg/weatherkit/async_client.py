from .config import ClientConfig
from .errors import ApiError
from .models import parse_station
from .transport import AsyncHttpTransport


class AsyncClient:
    def __init__(self, config=None, transport=None):
        self.config = config or ClientConfig()
        self.transport = transport or AsyncHttpTransport(self.config)

    async def _get(self, path, params=None):
        data = await self.transport.get_json(path, params)
        if "error" in data:
            raise ApiError(data.get("status", 500), data["error"])
        return data

    async def get_station(self, station_id):
        return parse_station(await self._get(f"/v1/stations/{station_id}"))

    async def list_stations(self, network):
        query = {"network": network, "per_page": self.config.page_size}
        data = await self._get("/v1/stations", {**query, "page": 1})
        total = data.get("total_pages", 1)
        results = [parse_station(item) for item in data["stations"]]
        page = 2
        while page < total:
            data = await self._get("/v1/stations", {**query, "page": page})
            results.extend(parse_station(item) for item in data["stations"])
            page += 1
        return results
