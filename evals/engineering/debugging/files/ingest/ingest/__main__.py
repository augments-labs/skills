import sys

from .loader import load_file
from .sink import write_records


def main(argv):
    if len(argv) != 2:
        print("usage: python3 -m ingest BATCH.jsonl", file=sys.stderr)
        return 2
    records = load_file(argv[1])
    write_records(records)
    print(f"imported {len(records)} records")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
