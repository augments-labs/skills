import sys

from .engine import lint_file


def main(argv=None):
    paths = sys.argv[1:] if argv is None else argv
    status = 0
    for path in paths:
        for finding in lint_file(path):
            print(finding.format(path))
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
