import json
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

TS_FORMAT = "%Y-%m-%dT%H:%M:%S%z"
REQUIRED = ("id", "name", "city", "amount", "ts")


@dataclass(frozen=True)
class Record:
    id: str
    name: str
    city: str
    amount: Decimal
    ts: datetime


class RecordError(ValueError):
    pass


def parse_ts(value):
    return datetime.strptime(value, TS_FORMAT)


def parse_line(raw):
    """Parse one batch line (bytes) into a Record."""
    text = raw.decode("utf-8")
    data = json.loads(text, parse_float=Decimal)
    missing = [field for field in REQUIRED if field not in data]
    if missing:
        raise RecordError("missing fields: " + ", ".join(missing))
    return Record(
        id=str(data["id"]),
        name=data["name"],
        city=data["city"],
        amount=Decimal(str(data["amount"])),
        ts=parse_ts(data["ts"]),
    )
