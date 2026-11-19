# weatherkit

A small client for the station listing API. It has a blocking client and an
asyncio client with the same methods.

## Usage

```python
from weatherkit import ClientConfig, SyncClient

client = SyncClient(ClientConfig.from_env())
for station in client.list_stations("nordic"):
    print(station.id, station.name)
```

`list_stations(network)` returns every station in the network. You will
recieve a list of `Station` objects, in the order the API returns them.

The asyncio client works the same way:

```python
import asyncio
from weatherkit import AsyncClient, ClientConfig

stations = asyncio.run(AsyncClient(ClientConfig.from_env()).list_stations("nordic"))
```

## Configuration

| Variable | Default |
| --- | --- |
| `WEATHERKIT_URL` | `https://api.weatherkit.example` |
| `WEATHERKIT_API_KEY` | none |
| `WEATHERKIT_PAGE_SIZE` | `100` |

## Command line

```bash
python3 -m weatherkit.cli list --offline
python3 -m weatherkit.cli show NO-0001 --offline
```

`--offline` reads the bundled sample network instead of calling the API.

## Tests

```bash
python3 -m unittest discover -s tests -t .
```
