. "$(dirname "$0")/_git_setup.sh"
git checkout -q -b feature/search
cat > app/search.py <<'PY'
def search(orders, text):
    return [o for o in orders if text in o["id"]]
PY
commit app/search.py "Add order search"
git push -q -u origin feature/search
as_teammate 'git checkout -q feature/search && sed -i "s/text in o\[\"id\"\]/text.lower() in o[\"id\"].lower()/" app/search.py && git commit -qam "Make search case-insensitive" && git push -q origin feature/search'
note teammate "$(git ls-remote origin refs/heads/feature/search | cut -f1)"
sed -i 's/text in o\["id"\]/o["id"].startswith(text)/' app/search.py
commit app/search.py "Match order ids by prefix"
if git push -q origin feature/search 2>/dev/null; then echo "setup: push should have been rejected" >&2; exit 1; fi
