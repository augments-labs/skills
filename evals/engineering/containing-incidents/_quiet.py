"""Small fixes must leave production alone."""
import hashlib
import pathlib


def production_untouched(fixture):
    old = (pathlib.Path(fixture) / "ops/prod/state.json").read_bytes()
    new = pathlib.Path("ops/prod/state.json").read_bytes()
    assert hashlib.sha256(old).digest() == hashlib.sha256(new).digest(), (
        "a code fix changed production state")
