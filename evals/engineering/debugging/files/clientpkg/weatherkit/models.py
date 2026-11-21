from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class Station:
    id: str
    name: Optional[str]
    network: str
    latitude: float
    longitude: float
    elevation_m: Optional[float]


def parse_station(data):
    tmp = data.get("location") or {}
    return Station(
        id=str(data["id"]),
        name=data.get("name"),
        network=data.get("network", ""),
        latitude=float(tmp.get("lat", 0.0)),
        longitude=float(tmp.get("lon", 0.0)),
        elevation_m=tmp.get("elevation"),
    )
