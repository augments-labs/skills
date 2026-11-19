import argparse
import json
import sys
from pathlib import Path

from .config import ClientConfig
from .format import station_detail, station_row
from .models import parse_station
from .sync_client import SyncClient

SAMPLE = Path(__file__).resolve().parent / "data" / "stations.json"


def load_sample():
    with SAMPLE.open(encoding="utf-8") as f:
        return [parse_station(item) for item in json.load(f)["stations"]]


def main(argv=None):
    parser = argparse.ArgumentParser(prog="weatherkit")
    parser.add_argument("--network", default="nordic")
    sub = parser.add_subparsers(dest="command", required=True)
    list_cmd = sub.add_parser("list", help="list the stations in a network")
    list_cmd.add_argument("--offline", action="store_true")
    show_cmd = sub.add_parser("show", help="show one station")
    show_cmd.add_argument("station_id")
    show_cmd.add_argument("--offline", action="store_true")
    args = parser.parse_args(argv)

    if args.command == "list":
        if args.offline:
            stations = load_sample()
        else:
            stations = SyncClient(ClientConfig.from_env()).list_stations(args.network)
        for station in stations:
            print(station_row(station))
        return 0

    if args.offline:
        found = [s for s in load_sample() if s.id == args.station_id]
        if not found:
            print(f"no station {args.station_id}", file=sys.stderr)
            return 1
        station = found[0]
    else:
        station = SyncClient(ClientConfig.from_env()).get_station(args.station_id)
    print(station_detail(station))
    return 0


if __name__ == "__main__":
    sys.exit(main())
