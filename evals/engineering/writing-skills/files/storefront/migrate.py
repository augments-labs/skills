"""Migration runner.

Applies `NNNN_<slug>.up.sql` files in number order, core first, then each
plugin. Each migration runs inside a transaction unless its first line is
exactly `-- migrate: no-transaction`. `down N` runs the `.down.sql` files
from the newest back to migration N.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
NAME = re.compile(r"^(\d{4})_([a-z0-9_]+)\.(up|down)\.sql$")
NO_TX = "-- migrate: no-transaction"


def migration_dirs():
    dirs = [os.path.join(ROOT, "migrations")]
    plugins = os.path.join(ROOT, "plugins")
    for name in sorted(os.listdir(plugins)):
        d = os.path.join(plugins, name, "migrations")
        if os.path.isdir(d):
            dirs.append(d)
    return dirs


def plan(directory, direction="up"):
    """The files to run, by number. The first file seen for a number wins."""
    seen = {}
    for name in sorted(os.listdir(directory)):
        m = NAME.match(name)
        if m and m.group(3) == direction:
            seen.setdefault(int(m.group(1)), name)
    return [seen[k] for k in sorted(seen)]


def needs_transaction(path):
    with open(path) as f:
        return f.readline().rstrip("\n") != NO_TX


def main(argv):
    if not argv or argv[0] not in ("up", "down", "plan"):
        print("usage: migrate.py up | down N | plan", file=sys.stderr)
        return 2
    for d in migration_dirs():
        for name in plan(d, "down" if argv[0] == "down" else "up"):
            tx = "tx" if needs_transaction(os.path.join(d, name)) else "no-tx"
            print(f"{os.path.relpath(os.path.join(d, name), ROOT)}\t{tx}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
