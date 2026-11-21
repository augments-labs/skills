import time

from .errors import DuplicateSource, UnknownSource

MIN_INTERVAL = 10


class Syncer:
    def __init__(self, store, interval=60):
        self.store = store
        self._sources = {}
        self._interval = interval
        self._last_run = None

    def add_source(self, source):
        if source.name in self._sources:
            raise DuplicateSource(source.name)
        self._sources[source.name] = source

    def remove_source(self, name):
        if name not in self._sources:
            raise UnknownSource(name)
        del self._sources[name]

    def rename_source(self, old, new):
        if old not in self._sources:
            raise UnknownSource(old)
        if new in self._sources:
            raise DuplicateSource(new)
        source = self._sources.pop(old)
        source.name = new
        self._sources[new] = source

    def set_interval(self, seconds):
        if seconds < MIN_INTERVAL:
            raise ValueError(f"interval must be at least {MIN_INTERVAL} seconds")
        self._interval = seconds

    def clear(self):
        self._sources.clear()

    def list_sources(self):
        return list(self._sources)

    def status(self):
        return {"sources": len(self._sources), "interval": self._interval,
                "last_run": self._last_run}

    def run(self, progress=None):
        """Pull every source once, in order. `progress(name, done, total)` is
        called after each source is stored."""
        sources = list(self._sources.values())
        for done, source in enumerate(sources, start=1):
            self.store.write(source.name, source.fetch())
            if progress is not None:
                progress(source.name, done, len(sources))
        self._last_run = time.time()
