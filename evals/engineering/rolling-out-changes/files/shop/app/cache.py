"""A small in-process cache with a time-to-live."""
import time

_store = {}


def get(key):
    hit = _store.get(key)
    if hit is None:
        return None
    value, expires = hit
    if time.monotonic() > expires:
        del _store[key]
        return None
    return value


def set(key, value, ttl=300):
    _store[key] = (value, time.monotonic() + ttl)


def clear():
    _store.clear()
