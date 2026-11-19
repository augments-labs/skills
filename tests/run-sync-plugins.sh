#!/usr/bin/env bash
# Offline tests for scripts/sync-plugins.sh and the plugin checks in
# scripts/validate.sh. Each case runs in a throwaway copy of the working tree.
# No harness CLI, no network, no model call.

set -uo pipefail
export LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0 failed=0
ok() { pass=$((pass + 1)); echo "  ok    $*"; }
bad() { failed=$((failed + 1)); echo "  FAIL  $*"; }

# Fresh copy of the tracked and untracked-but-not-ignored files.
fresh() {
  work="$tmp/case$((pass + failed))"
  rm -rf "$work"
  mkdir -p "$work"
  (cd "$repo" && git ls-files -co --exclude-standard | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done | tar -cf - -T -) | tar -xf - -C "$work"
  (cd "$work" && git init -q)
}

run() { (cd "$work" && bash "$@" >"$tmp/out" 2>&1); }
expect_ok() { local d="$1"; shift; if run "$@"; then ok "$d"; else bad "$d"; sed 's/^/        /' "$tmp/out"; fi; }
expect_fail() { # description, pattern, command...
  local d="$1" pat="$2"; shift 2
  if run "$@"; then bad "$d (exit 0)"; sed 's/^/        /' "$tmp/out"
  elif grep -qE -- "$pat" "$tmp/out"; then ok "$d"
  else bad "$d (no /$pat/ in output)"; sed 's/^/        /' "$tmp/out"; fi
}

skill() { # dir, name, body
  mkdir -p "$work/$1"
  printf -- '---\nname: %s\ndescription: "Sample %s skill. Use when testing plugin sync. Skip real work."\n---\n\n# Sample\n\n%s\n' \
    "$2" "$2" "$3" > "$work/$1/SKILL.md"
}

plugin_dir() { printf '%s/plugins/engineering-skills' "$work"; }

echo "sync-plugins.sh"

fresh
expect_ok "committed bundle is in sync" scripts/sync-plugins.sh --check

fresh
skill skills/engineering/sample-skill sample-skill "Load \`references/notes.md\` when the sample needs notes."
mkdir -p "$work/skills/engineering/sample-skill/references"
echo "# Notes" > "$work/skills/engineering/sample-skill/references/notes.md"
skill skills/in-progress/wip-skill wip-skill "Work in progress."
skill skills/deprecated/old-skill old-skill "Retired."
mkdir -p "$work/evals/engineering/sample-skill/distilled" "$work/hooks/engineering/lib" "$work/hooks/engineering/config" "$work/hooks/engineering/tests"
cp "$work/skills/engineering/sample-skill/SKILL.md" "$work/evals/engineering/sample-skill/distilled/SKILL.md"
echo 'echo check' > "$work/hooks/engineering/lib/check.sh"
echo '{"hooks": {}}' > "$work/hooks/engineering/config/claude-code.json"
echo '{"hooks": {}}' > "$work/hooks/engineering/config/codex.json"
echo '{"guard": {}}' > "$work/hooks/engineering/config/antigravity.json"
echo 'echo test' > "$work/hooks/engineering/tests/test.sh"
expect_fail "new canonical content is reported as drift" "out of sync: .*sample-skill/SKILL.md is missing" scripts/sync-plugins.sh --check
expect_ok "sync rebuilds the bundle" scripts/sync-plugins.sh
expect_ok "rebuilt bundle is in sync" scripts/sync-plugins.sh --check
p="$(plugin_dir)"
[ -f "$p/skills/sample-skill/SKILL.md" ] && [ -f "$p/skills/sample-skill/references/notes.md" ] &&
  ok "promoted skill copied flat with its references" || bad "promoted skill not copied flat"
[ ! -e "$p/skills/wip-skill" ] && [ ! -e "$p/skills/old-skill" ] && ! find "$p" -path '*evals*' | grep -q . &&
  ok "in-progress, deprecated, and evals never ship" || bad "unshipped content entered the bundle"
cmp -s "$p/hooks/hooks.json" "$work/hooks/engineering/config/claude-code.json" &&
  cmp -s "$p/hooks/codex-hooks.json" "$work/hooks/engineering/config/codex.json" &&
  cmp -s "$p/hooks.json" "$work/hooks/engineering/config/antigravity.json" &&
  ok "per-harness hook configs land where each harness reads them" || bad "hook configs misplaced"
[ -f "$p/hooks/lib/check.sh" ] && [ ! -e "$p/hooks/tests" ] && [ ! -e "$p/hooks/config" ] &&
  ok "hook scripts ship; hook tests and raw configs do not" || bad "hook tree layout wrong"
if command -v python3 >/dev/null 2>&1; then
  if python3 - "$p" <<'PY'
import json, sys
root = sys.argv[1]
c = json.load(open(root + "/.codex-plugin/plugin.json"))
for m in (".claude-plugin", ".antigravity-plugin"):
    j = json.load(open(f"{root}/{m}/plugin.json"))
    assert j["name"] == "engineering-skills" and "email" not in json.dumps(j), m
assert c["skills"] == "./skills/" and c["hooks"] == "./hooks/codex-hooks.json", c
PY
  then ok "manifests parse; Codex manifest points at skills and hooks"; else bad "manifest contents wrong"; fi
fi
expect_ok "validate.sh --strict passes on the synced copy" scripts/validate.sh --strict

sed -i.bak 's/"version": "[^"]*"/"version": "9.9.9"/' "$work/package.json" && rm -f "$work/package.json.bak"
expect_fail "version bump is reported as drift" "plugin.json differs" scripts/sync-plugins.sh --check
run scripts/sync-plugins.sh
grep -q '"version": "9.9.9"' "$p/.claude-plugin/plugin.json" && grep -q '"version": "9.9.9"' "$p/.codex-plugin/plugin.json" &&
  grep -q '"version": "9.9.9"' "$p/.antigravity-plugin/plugin.json" && ok "versions stamped from package.json" ||
  bad "versions not stamped"

echo "tampered" >> "$p/skills/sample-skill/SKILL.md"
expect_fail "hand edit inside the bundle is drift" "sample-skill/SKILL.md differs" scripts/sync-plugins.sh --check
run scripts/sync-plugins.sh
echo "stray" > "$p/skills/sample-skill/stray.md"
expect_fail "file with no canonical source is drift" "stray.md has no canonical source" scripts/sync-plugins.sh --check
expect_fail "validate.sh fails on drift" "plugins/ is out of sync" scripts/validate.sh
rm -f "$p/skills/sample-skill/stray.md"

mkdir -p "$work/skills/games/sample-game"
skill skills/games/sample-game sample-game "Game."
expect_fail "unregistered pack is refused" "no metadata|not registered" scripts/sync-plugins.sh
rm -rf "$work/skills/games"

mkdir -p "$work/plugins/orphan-skills" && echo '{}' > "$work/plugins/orphan-skills/x.json"
expect_fail "orphan bundle is refused" "orphan-skills/ has no canonical pack" scripts/sync-plugins.sh --check
rm -rf "$work/plugins/orphan-skills"

echo "validate.sh dangling references"

fresh
skill skills/engineering/sample-skill sample-skill "Use the \`wip-skill\` skill first."
skill skills/in-progress/wip-skill wip-skill "Draft."
run scripts/sync-plugins.sh
expect_fail "naming an unpromoted skill fails" "names the 'wip-skill' skill, which is not promoted" scripts/validate.sh

fresh
skill skills/engineering/sample-skill sample-skill "See [the draft](../../in-progress/wip-skill/SKILL.md)."
run scripts/sync-plugins.sh
expect_fail "linking into in-progress fails" "unshipped skill path|leaves the pack" scripts/validate.sh

fresh
skill skills/engineering/sample-skill sample-skill "See [verifying](../verifying/SKILL.md) when done."
run scripts/sync-plugins.sh
expect_fail "linking to an unpromoted sibling fails" "links to the 'verifying' skill" scripts/validate.sh

fresh
skill skills/engineering/sample-skill sample-skill "Load \`references/missing.md\` when stuck."
run scripts/sync-plugins.sh
expect_fail "missing support file fails" "support file 'references/missing.md'" scripts/validate.sh

fresh
skill skills/in-progress/wip-skill wip-skill "Hand off to the \`writing-plans\` skill."
expect_fail "in-progress skill naming an unshipped skill fails" "names the 'writing-plans' skill" scripts/validate.sh

fresh
skill skills/engineering/first-skill first-skill "Then use the \`second-skill\` skill; see [it](../second-skill/SKILL.md)."
skill skills/engineering/second-skill second-skill "Load \`references/r.md\` when needed."
mkdir -p "$work/skills/engineering/second-skill/references" && echo "# R" > "$work/skills/engineering/second-skill/references/r.md"
run scripts/sync-plugins.sh
expect_ok "references between promoted skills pass" scripts/validate.sh --strict

echo
echo "run-sync-plugins: $pass passed, $failed failed"
[ "$failed" -eq 0 ]
