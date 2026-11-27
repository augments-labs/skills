. "$(dirname "$0")/_git_setup.sh"
git checkout -q -b fix/typo
sed -i 's/recieve/receive/' README.md
commit README.md "Fix typo in README"
git checkout -q -b feat/report main
cat > app/report.py <<'PY'
def total(orders):
    return sum(o["amount_cents"] for o in orders if o["status"] == "paid")
PY
commit app/report.py "Add a paid total report"
git push -q -u origin feat/report
git checkout -q main
git merge -q --no-ff -m "Merge fix/typo" fix/typo
git merge -q --no-ff -m "Merge feat/report" feat/report
git push -q origin main
git checkout -q -b spike/cache
cat > app/cache.py <<'PY'
_CACHE = {}


def cached_export(key, build):
    if key not in _CACHE:
        _CACHE[key] = build()
    return _CACHE[key]
PY
commit app/cache.py "Spike an export cache"
printf '\n\ndef clear():\n    _CACHE.clear()\n' >> app/cache.py
commit app/cache.py "Let the cache be cleared"
note spike "$(git rev-parse HEAD)"
git checkout -q main
WT="$(cd .. && pwd)/wt-report"
git worktree add -q "$WT" feat/report
printf '\n\ndef quarterly_totals(orders):\n    raise NotImplementedError  # half done, keep\n' >> "$WT/app/report.py"
note worktree "$WT"
