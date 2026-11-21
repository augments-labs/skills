"""Exit 0 when a station without a name shows as 'Unnamed station' and the offline list works."""
import os
import subprocess
import sys

CHILD = r'''
import sys

sys.path.insert(0, sys.argv[1])
from weatherkit.format import display_name
from weatherkit.models import Station


def station(name):
    return Station(id="X1", name=name, network="test", latitude=0.0, longitude=0.0, elevation_m=1.0)


problems = []
got = display_name(station(None))
if got != "Unnamed station":
    problems.append("display_name(None) is %r" % (got,))
got = display_name(station(" oslo "))
if got != "Oslo":
    problems.append("display_name(' oslo ') is %r" % (got,))
if problems:
    print("; ".join(problems))
    sys.exit(1)
'''


def run(argv, workdir, timeout):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    try:
        p = subprocess.run(argv, cwd=workdir, env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "timed out after %ds" % timeout
    return p.returncode, p.stdout.decode("utf-8", "replace").strip()


def main():
    workdir = os.path.abspath(sys.argv[1])
    rc, out = run([sys.executable, "-I", "-c", CHILD, workdir], workdir, 60)
    if rc != 0:
        print("display_name: " + (out.splitlines()[-1] if out else "exit %s" % rc))
        return 1
    rc, out = run([sys.executable, "-m", "weatherkit.cli", "list", "--offline"], workdir, 60)
    if rc != 0:
        print("weatherkit.cli list --offline: " + (out.splitlines()[-1] if out else "exit %s" % rc))
        return 1
    if "Unnamed station" not in out or "Oslo Blindern" not in out:
        print("weatherkit.cli list --offline does not show 'Unnamed station' and 'Oslo Blindern'")
        return 1
    return 0


if __name__ == "__main__":
    try:
        code = main()
    except BaseException as exc:  # a crash in the code under test is a failure, not a verifier error
        print("verifier could not check the work tree: %s: %s" % (type(exc).__name__, exc))
        code = 1
    sys.exit(code)
