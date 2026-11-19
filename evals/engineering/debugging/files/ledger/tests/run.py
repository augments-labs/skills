"""Run the unit tests and print a one-line summary."""
import sys
import time
import unittest


def main():
    suite = unittest.defaultTestLoader.discover("tests", top_level_dir=".")
    start = time.monotonic()
    result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
    failed = len(result.failures) + len(result.errors)
    skipped = len(result.skipped)
    passed = result.testsRun - failed - skipped
    print(f"{passed} passed, {failed} failed, {skipped} skipped "
          f"in {time.monotonic() - start:.2f}s")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
