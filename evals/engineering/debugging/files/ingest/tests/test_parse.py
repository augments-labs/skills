import json
import unittest
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from ingest import RecordError, parse_line


def line(**fields):
    data = {"id": "p-1", "name": "Ada Brook", "city": "Leeds",
            "amount": 19.5, "ts": "2026-02-28T09:30:00+00:00"}
    data.update(fields)
    return json.dumps(data).encode("utf-8")


class ParseLineTests(unittest.TestCase):
    def test_parses_a_record(self):
        record = parse_line(line())
        self.assertEqual(record.id, "p-1")
        self.assertEqual(record.name, "Ada Brook")
        self.assertEqual(record.amount, Decimal("19.5"))

    def test_timestamp_keeps_offset(self):
        record = parse_line(line(ts="2026-02-28T09:30:00+02:00"))
        self.assertEqual(record.ts, datetime(2026, 2, 28, 7, 30, tzinfo=timezone.utc))
        self.assertEqual(record.ts.utcoffset(), timedelta(hours=2))

    def test_integer_amount(self):
        self.assertEqual(parse_line(line(amount=7)).amount, Decimal("7"))

    def test_missing_field_is_rejected(self):
        with self.assertRaises(RecordError):
            parse_line(b'{"id": "p-1", "name": "Ada Brook"}')


if __name__ == "__main__":
    unittest.main()
