. "$(dirname "$0")/_git_setup.sh"
git checkout -q -b spike/cache
cat > app/cache.py <<'PY'
_CACHE = {}


def cached_export(key, build):
    if key not in _CACHE:
        _CACHE[key] = build()
    return _CACHE[key]
PY
commit app/cache.py "Spike an export cache"
git push -q -u origin spike/cache
as_teammate 'git checkout -q spike/cache && printf "\n\ndef invalidate(key):\n    _CACHE.pop(key, None)\n" >> app/cache.py && git commit -qam "Add cache invalidation for the nightly job" && git push -q origin spike/cache'
note teammate "$(git ls-remote origin refs/heads/spike/cache | cut -f1)"
git checkout -q main
