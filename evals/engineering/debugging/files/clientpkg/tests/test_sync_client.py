import unittest

from weatherkit import ApiError, SyncClient

from .fakes import FakeTransport, page_payload, station_payload


class SyncClientTests(unittest.TestCase):
    def test_list_stations_single_page(self):
        stations = [station_payload(n) for n in range(1, 4)]
        transport = FakeTransport({"/v1/stations": page_payload(stations)})
        result = SyncClient(transport=transport).list_stations("test")
        self.assertEqual([s.id for s in result], ["ST00001", "ST00002", "ST00003"])
        self.assertEqual(transport.calls[0][1]["network"], "test")
        self.assertEqual(transport.calls[0][1]["page"], 1)

    def test_list_stations_empty_network(self):
        transport = FakeTransport({"/v1/stations": page_payload([])})
        self.assertEqual(SyncClient(transport=transport).list_stations("test"), [])

    def test_get_station(self):
        transport = FakeTransport({"/v1/stations/ST00007": station_payload(7)})
        station = SyncClient(transport=transport).get_station("ST00007")
        self.assertEqual(station.id, "ST00007")
        self.assertEqual(station.elevation_m, 7)

    def test_error_payload_raises(self):
        transport = FakeTransport({"/v1/stations": {"error": "unknown network", "status": 404}})
        with self.assertRaises(ApiError) as caught:
            SyncClient(transport=transport).list_stations("nope")
        self.assertEqual(caught.exception.status, 404)


if __name__ == "__main__":
    unittest.main()
