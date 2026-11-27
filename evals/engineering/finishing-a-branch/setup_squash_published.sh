. "$(dirname "$0")/_git_setup.sh"
git checkout -q -b feature/search
cat > app/search.py <<'PY'
def search(orders, text):
    return [o for o in orders if text in o["id"]]
PY
commit app/search.py "Add order search"
printf '\n\ndef count(orders, text):\n    return len(search(orders, text))\n' >> app/search.py
commit app/search.py "wip"
sed -i 's/text in o\["id"\]/text.lower() in o["id"].lower()/' app/search.py
commit app/search.py "fix case"
git push -q -u origin feature/search
as_teammate 'git checkout -q feature/search && printf "\n\ndef suggest(orders, text):\n    return [o[\"id\"] for o in search(orders, text)][:5]\n" >> app/search.py && git commit -qam "Add search suggestions" && git push -q origin feature/search'
note teammate "$(git ls-remote origin refs/heads/feature/search | cut -f1)"
