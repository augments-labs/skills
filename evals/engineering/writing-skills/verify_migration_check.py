"""The trap: the repo-local skill is valid and its check is not hollow.

The agent was asked for a project skill under .agents/skills/ whose
scripts/check.sh, run from the repo root with no arguments, exits non-zero
on the migration problems in docs/incidents.md. The check runs against
fresh copies of the final tree: as it is and with new valid migrations it
must exit 0; with each incident's problem planted again under new names it
must exit non-zero.
"""
import glob
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("_skillcheck", os.path.join(HERE, "_skillcheck.py"))
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)

work = sys.argv[1]
checks = sorted(glob.glob(os.path.join(work, ".agents", "skills", "*", "scripts", "check.sh")))
if len(checks) != 1:
    print(f"want one .agents/skills/*/scripts/check.sh, found {len(checks)}")
    sys.exit(1)
skill_dir = os.path.dirname(os.path.dirname(checks[0]))
problems = sc.check_skill(skill_dir)
if problems:
    print("skill invalid:", "; ".join(problems))
    sys.exit(1)
rel_check = os.path.relpath(checks[0], work)

CORE = "migrations"
BILLING = "plugins/billing/migrations"


def next_number(tree, d):
    nums = [int(m.group(1)) for f in os.listdir(os.path.join(tree, d))
            if (m := re.match(r"^(\d{4})_", f))]
    return max(nums, default=0) + 1


def put(tree, d, n, slug, up=None, down=None):
    for kind, text in (("up", up), ("down", down)):
        if text is not None:
            with open(os.path.join(tree, d, f"{n:04d}_{slug}.{kind}.sql"), "w") as f:
                f.write(text)


def valid_additions(t):
    n = next_number(t, CORE)
    put(t, CORE, n, "add_gift_wrap", "ALTER TABLE orders ADD COLUMN gift_wrap BOOLEAN NOT NULL DEFAULT false;\n",
        "ALTER TABLE orders DROP COLUMN gift_wrap;\n")
    put(t, CORE, n + 1, "index_orders_total",
        "-- migrate: no-transaction\n-- Large table: build the index without locking writes.\n"
        "CREATE INDEX CONCURRENTLY orders_total_idx ON orders (total_cents);\n",
        "-- migrate: no-transaction\nDROP INDEX CONCURRENTLY orders_total_idx;\n")
    put(t, CORE, n + 2, "add_status_on_hold",
        "-- migrate: no-transaction\nALTER TYPE order_status ADD VALUE 'on_hold';\n",
        "-- Postgres cannot drop an enum value.\nSELECT 1;\n")
    b = next_number(t, BILLING)
    put(t, BILLING, b, "add_credit_notes", "CREATE TABLE credit_notes (id BIGSERIAL PRIMARY KEY, invoice_id BIGINT NOT NULL);\n",
        "DROP TABLE credit_notes;\n")


def duplicate_number(t):
    n = next_number(t, CORE)
    put(t, CORE, n, "add_gift_wrap", "ALTER TABLE orders ADD COLUMN gift_wrap BOOLEAN;\n",
        "ALTER TABLE orders DROP COLUMN gift_wrap;\n")
    put(t, CORE, n, "add_loyalty_points", "ALTER TABLE customers ADD COLUMN loyalty_points INTEGER;\n",
        "ALTER TABLE customers DROP COLUMN loyalty_points;\n")


def missing_down_core(t):
    put(t, CORE, next_number(t, CORE), "add_customer_phone", "ALTER TABLE customers ADD COLUMN phone TEXT;\n")


def missing_down_plugin(t):
    put(t, BILLING, next_number(t, BILLING), "add_credit_notes",
        "CREATE TABLE credit_notes (id BIGSERIAL PRIMARY KEY, invoice_id BIGINT NOT NULL);\n")


def duplicate_number_plugin(t):
    b = next_number(t, BILLING)
    put(t, BILLING, b, "add_credit_notes", "CREATE TABLE credit_notes (id BIGSERIAL PRIMARY KEY);\n",
        "DROP TABLE credit_notes;\n")
    put(t, BILLING, b, "add_invoice_due_date", "ALTER TABLE invoices ADD COLUMN due_date DATE;\n",
        "ALTER TABLE invoices DROP COLUMN due_date;\n")


def concurrent_index_no_header(t):
    put(t, CORE, next_number(t, CORE), "index_orders_customer_id",
        "CREATE INDEX CONCURRENTLY orders_customer_id_idx ON orders (customer_id);\n",
        "-- migrate: no-transaction\nDROP INDEX CONCURRENTLY orders_customer_id_idx;\n")


def enum_value_header_on_line_two(t):
    put(t, CORE, next_number(t, CORE), "add_status_disputed",
        "-- Customers can now dispute a delivered order.\n-- migrate: no-transaction\n"
        "ALTER TYPE order_status ADD VALUE 'disputed';\n",
        "-- Postgres cannot drop an enum value.\nSELECT 1;\n")


def concurrent_index_plugin_no_header(t):
    put(t, BILLING, next_number(t, BILLING), "index_invoices_issued_at",
        "CREATE INDEX CONCURRENTLY invoices_issued_at_idx ON invoices (issued_at);\n",
        "-- migrate: no-transaction\nDROP INDEX CONCURRENTLY invoices_issued_at_idx;\n")


def run_check(tree):
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.environ.get("HOME", tree), "LC_ALL": "C.UTF-8"}
    try:
        p = subprocess.run(["bash", rel_check], cwd=tree, env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    except subprocess.TimeoutExpired:
        return None, "timeout"
    return p.returncode, p.stdout.decode(errors="replace")[-400:]


def copy_tree():
    d = tempfile.mkdtemp(prefix="wsk-")
    t = os.path.join(d, "repo")
    shutil.copytree(work, t, symlinks=True)
    return t


failed = []
for label, mutate, want_ok in [
        ("clean", None, True),
        ("valid-additions", valid_additions, True),
        ("duplicate-number", duplicate_number, False),
        ("missing-down", missing_down_core, False),
        ("missing-down-in-plugin", missing_down_plugin, False),
        ("duplicate-number-in-plugin", duplicate_number_plugin, False),
        ("concurrent-index-without-header", concurrent_index_no_header, False),
        ("enum-value-header-on-line-2", enum_value_header_on_line_two, False),
        ("plugin-concurrent-index-without-header", concurrent_index_plugin_no_header, False)]:
    tree = copy_tree()
    try:
        if mutate:
            mutate(tree)
        rc, out = run_check(tree)
    finally:
        shutil.rmtree(os.path.dirname(tree), ignore_errors=True)
    ok = rc == 0 if want_ok else (rc not in (0, None))
    print(f"{label}: exit {rc} ({'ok' if ok else 'WRONG'})")
    if not ok:
        failed.append(label)
        print("  " + out.replace("\n", "\n  ").rstrip())
sys.exit(1 if failed else 0)
