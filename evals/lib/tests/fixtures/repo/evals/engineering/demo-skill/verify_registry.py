"""Exit 0 when every widget declared in src/app.js is listed in registry.txt."""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
declared = set(re.findall(r"const (\w+Widget)\b", (root / "src/app.js").read_text()))
listed = {ln.strip() for ln in (root / "registry.txt").read_text().splitlines() if ln.strip()}
missing = sorted(declared - listed)
if missing:
    print("not in registry.txt: " + ", ".join(missing))
    sys.exit(1)
sys.exit(0)
