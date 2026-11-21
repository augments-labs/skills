"""The runbook case: one valid project skill that keeps the runbook's guards.

The case's skill-triggering assertion scores the written description's
triggering on catalog-queries.json.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("_skillcheck", os.path.join(HERE, "_skillcheck.py"))
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)

skills = os.path.join(sys.argv[1], ".agents", "skills")
dirs = sorted(d for d in os.listdir(skills)) if os.path.isdir(skills) else []
dirs = [d for d in dirs if os.path.isfile(os.path.join(skills, d, "SKILL.md"))]
if len(dirs) != 1:
    print(f"expected one skill under .agents/skills/, found {dirs}")
    sys.exit(1)
skill = os.path.join(skills, dirs[0])
problems = sc.check_skill(skill)
if problems:
    print("; ".join(problems))
    sys.exit(1)
_, body, _ = sc.frontmatter(os.path.join(skill, "SKILL.md"))
GUARDS = {
    "resume writes within 20 minutes": r"20\s*min",
    "counts within 0.5% before swapping": r"0\.5\s*%",
    "stop if a shadow rebuild is already in progress": r"-shadow|shadow\b[^.\n]*(already|in progress|half)|(already|in progress|half)[^.\n]*shadow",
    "never delete the live index": r"(never|not|n't)\s+delete",
    "keep the old index 24 hours": r"24\s*h",
}
missing = [g for g, rx in GUARDS.items() if not re.search(rx, body, re.IGNORECASE)]
if missing:
    print("SKILL.md lost: " + "; ".join(missing))
    sys.exit(1)
sys.exit(0)
