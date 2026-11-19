"""Remove the scratch ledgers the tests leave in .test-tmp/."""
import os
import sys

from tests.support import DATA_NAME, SCRATCH


def main():
    if not SCRATCH.exists():
        return 0
    for case_dir in sorted(SCRATCH.iterdir()):
        data = case_dir / DATA_NAME
        if data.exists():
            os.remove(data)
        os.rmdir(case_dir)
    os.rmdir(SCRATCH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
