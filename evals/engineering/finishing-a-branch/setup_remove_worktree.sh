. "$(dirname "$0")/_git_setup.sh"
printf 'notes/\n' >> .gitignore
commit .gitignore "Keep personal notes out of git"
git push -q origin main
git checkout -q -b feat/report
cat > app/report.py <<'PY'
def total(orders):
    return sum(o["amount_cents"] for o in orders if o["status"] == "paid")
PY
commit app/report.py "Add a paid total report"
git push -q -u origin feat/report
git checkout -q main
git merge -q --no-ff -m "Merge feat/report" feat/report
git push -q origin main
WT="$(cd .. && pwd)/wt-report"
git worktree add -q "$WT" feat/report
mkdir -p "$WT/notes"
cat > "$WT/notes/quarterly-plan.md" <<'MD'
# Quarterly totals plan

Group paid orders by quarter, then by currency. Billing wants Q1 to start
in February. Ask finance before changing the rounding.
MD
note worktree "$WT"
