import json
import os
import tempfile
import threading
from pathlib import Path


class FileStore:
    """A tiny key-value store kept in one JSON file.

    Every call reads the file, so other processes see each change. Writes go
    to a temporary file that replaces the original in one step, and each call
    holds a lock so threads never see a half-written file.
    """

    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    def _load(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                return json.load(f)
        except FileNotFoundError:
            return {}

    def get(self, key, default=None):
        with self._lock:
            return self._load().get(key, default)

    def set(self, key, value):
        with self._lock:
            data = self._load()
            data[key] = value
            fd, tmp = tempfile.mkstemp(dir=self.path.parent, prefix=".store-", suffix=".json")
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(data, f, sort_keys=True)
                os.replace(tmp, self.path)
            except BaseException:
                os.unlink(tmp)
                raise
