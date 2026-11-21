# syncer

Pulls records from upstream sources into the local store on a schedule.

- `syncer/engine.py`: `Syncer` holds the sources and the interval, and `run()`
  pulls every source once, in the order they were added.
- `syncer/sources.py`: `Source` and the built-in `StaticSource`.
- `syncer/store.py`: `MemoryStore`, the store used by the tests and the dev server.
- `syncer/errors.py`: the package's exceptions.

## Development

Every behavior change ships with unit tests under `tests/`. Run them with:

```bash
python3 -m unittest discover -s tests -t .
```
