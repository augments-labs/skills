import unittest

from weatherkit.models import parse_station


class ParseStationTests(unittest.TestCase):
    def test_full_record(self):
        station = parse_station(
            {
                "id": 42,
                "name": "harbour",
                "network": "coast",
                "location": {"lat": 59.9, "lon": 10.7, "elevation": 3.5},
            }
        )
        self.assertEqual(station.id, "42")
        self.assertEqual(station.network, "coast")
        self.assertEqual(station.latitude, 59.9)
        self.assertEqual(station.elevation_m, 3.5)

    def test_missing_location(self):
        station = parse_station({"id": "A1", "name": "roof"})
        self.assertEqual(station.latitude, 0.0)
        self.assertIsNone(station.elevation_m)
        self.assertEqual(station.network, "")


if __name__ == "__main__":
    unittest.main()
