import asyncio
import unittest

from weatherkit import ApiError, AsyncClient

from .fakes import FakeAsyncTransport, page_payload, station_payload


class AsyncClientTests(unittest.TestCase):
    def test_list_stations_single_page(self):
        stations = [station_payload(n) for n in range(1, 6)]
        transport = FakeAsyncTransport({"/v1/stations": page_payload(stations)})
        result = asyncio.run(AsyncClient(transport=transport).list_stations("test"))
        self.assertEqual(len(result), 5)
        self.assertEqual(result[-1].id, "ST00005")

    def test_get_station(self):
        transport = FakeAsyncTransport({"/v1/stations/ST00002": station_payload(2)})
        station = asyncio.run(AsyncClient(transport=transport).get_station("ST00002"))
        self.assertEqual(station.name, "station 2")

    def test_error_payload_raises(self):
        transport = FakeAsyncTransport({"/v1/stations": {"error": "forbidden", "status": 403}})
        with self.assertRaises(ApiError):
            asyncio.run(AsyncClient(transport=transport).list_stations("test"))


if __name__ == "__main__":
    unittest.main()
