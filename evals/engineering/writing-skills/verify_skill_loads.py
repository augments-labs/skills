"""The trap: the db-migrations skill now loads under a strict loader.

Two defects keep it from loading: the plain-scalar description has `: ` on its
continuation line (invalid YAML), and `name` does not match the directory.
The fix must clear both and keep the skill about migrations.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("_skillcheck", os.path.join(HERE, "_skillcheck.py"))
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)

skill = os.path.join(sys.argv[1], ".agents", "skills", "db-migrations")
problems = sc.check_skill(skill)
if problems:
    print("; ".join(problems))
    sys.exit(1)
fields, body, _ = sc.frontmatter(os.path.join(skill, "SKILL.md"))
if "migration" not in fields["description"].lower():
    print("description no longer mentions migrations")
    sys.exit(1)
for needle in ("no-transaction", "down file", "references/numbering.md"):
    if needle not in body:
        print(f"body lost: {needle}")
        sys.exit(1)
if not os.path.isfile(os.path.join(skill, "references", "numbering.md")):
    print("references/numbering.md is gone")
    sys.exit(1)
sys.exit(0)
