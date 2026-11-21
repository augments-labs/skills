from .config import ClientConfig
from .errors import ApiError
from .models import parse_station
from .transport import HttpTransport


class SyncClient:
    def __init__(self, config=None, transport=None):
        self.config = config or ClientConfig()
        self.transport = transport or HttpTransport(self.config)

    def _get(self, path, params=None):
        data = self.transport.get_json(path, params)
        if "error" in data:
            raise ApiError(data.get("status", 500), data["error"])
        return data

    def get_station(self, station_id):
        return parse_station(self._get(f"/v1/stations/{station_id}"))

    def list_stations(self, network):
        params = {"network": network, "per_page": self.config.page_size, "page": 1}
        first = self._get("/v1/stations", params)
        stations = [parse_station(item) for item in first["stations"]]
        pages = first.get("total_pages", 1)
        for page in range(2, pages):
            data = self._get("/v1/stations", dict(params, page=page))
            stations.extend(parse_station(item) for item in data["stations"])
        return stations
