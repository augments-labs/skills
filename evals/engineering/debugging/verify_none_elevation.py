"""Exit 0 when a station without an elevation shows n/a and other stations still show feet."""
import os
import subprocess
import sys


def run(argv, workdir, timeout):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    try:
        p = subprocess.run(argv, cwd=workdir, env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "timed out after %ds" % timeout
    return p.returncode, p.stdout.decode("utf-8", "replace").strip()


def show(workdir, station_id):
    return run([sys.executable, "-m", "weatherkit.cli", "show", station_id, "--offline"], workdir, 60)


def main():
    workdir = os.path.abspath(sys.argv[1])
    rc, out = show(workdir, "DK-0005")
    if rc != 0:
        print("show DK-0005: " + (out.splitlines()[-1] if out else "exit %s" % rc))
        return 1
    if "n/a" not in out:
        print("show DK-0005 does not print n/a for the elevation")
        return 1
    rc, out = show(workdir, "NO-0001")
    if rc != 0:
        print("show NO-0001: " + (out.splitlines()[-1] if out else "exit %s" % rc))
        return 1
    if "308" not in out or "n/a" in out:
        print("show NO-0001 no longer prints its elevation in feet (308)")
        return 1
    return 0


if __name__ == "__main__":
    try:
        code = main()
    except BaseException as exc:  # a crash in the code under test is a failure, not a verifier error
        print("verifier could not check the work tree: %s: %s" % (type(exc).__name__, exc))
        code = 1
    sys.exit(code)
