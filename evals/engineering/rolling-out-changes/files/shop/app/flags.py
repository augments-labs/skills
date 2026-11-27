"""Feature flags, re-read on every call so a change reaches running processes."""
import json
import os
import zlib

DEFAULT_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config", "flags.json")


def _load():
    path = os.environ.get("FLAGS_FILE", DEFAULT_PATH)
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def is_enabled(name, subject=None):
    flag = _load().get(name)
    if flag is None or flag is False:
        return False
    if flag is True:
        return True
    percent = flag.get("percent", 0)
    if subject is None:
        return percent >= 100
    return zlib.crc32(f"{name}:{subject}".encode()) % 100 < percent
