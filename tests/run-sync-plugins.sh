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
  if python3 - "$p" "$work" <<'PY'
import json, os, sys
root, work = sys.argv[1], sys.argv[2]
def load(path):
    with open(path) as f:
        return json.load(f)
m = {d: load(f"{root}/{d}/plugin.json") for d in (".claude-plugin", ".codex-plugin", ".antigravity-plugin",
     ".grok-plugin", ".kimi-plugin", ".muse-plugin")}
for d, j in m.items():
    assert j["name"] == "engineering-skills" and "email" not in json.dumps(j), d
c = m[".codex-plugin"]
assert c["skills"] == "./skills/" and c["hooks"] == "./hooks/codex-hooks.json", c
# Grok Build would otherwise load hooks/hooks.json; Kimi Code gets no hooks entry.
assert m[".grok-plugin"]["skills"] == "./skills/" and m[".grok-plugin"]["hooks"] == [], m[".grok-plugin"]
assert m[".kimi-plugin"]["skills"] == ["./skills/"] and "hooks" not in m[".kimi-plugin"], m[".kimi-plugin"]
mu = m[".muse-plugin"]
assert mu["compat"] == {"source": "native", "manifestDir": ".muse-plugin"}, mu
names = sorted(os.listdir(root + "/skills"))
assert mu["capabilities"] == {"skills": [{"id": n, "path": f"skills/{n}/SKILL.md"} for n in names]}, mu
with open(root + "/plugin.yaml") as f:
    assert f.read().startswith("name: engineering-skills\n"), "plugin.yaml"
with open(root + "/__init__.py") as f, open(work + "/scripts/templates/hermes-init.py") as t:
    assert f.read() == t.read(), "__init__.py"
with open(root + "/index.js") as f:
    js = f.read()
assert 'id: "engineering-skills"' in js and "@PLUGIN@" not in js, "index.js"
assert load(work + "/.kimi-plugin/plugin.json")["skills"] == ["./plugins/engineering-skills/skills/"]
g = load(work + "/.grok-plugin/plugin.json")
assert g["skills"] == "./plugins/engineering-skills/skills/" and g["hooks"] == [], g
assert load(work + "/.grok-plugin/marketplace.json") == load(work + "/.claude-plugin/marketplace.json")
PY
  then ok "manifests parse and point each harness at the bundle's skills and hooks"; else bad "manifest contents wrong"; fi
fi
expect_ok "validate.sh --strict passes on the synced copy" scripts/validate.sh --strict

sed -i.bak 's/"version": "[^"]*"/"version": "9.9.9"/' "$work/package.json" && rm -f "$work/package.json.bak"
expect_fail "version bump is reported as drift" "plugin.json differs" scripts/sync-plugins.sh --check
run scripts/sync-plugins.sh
stamped=1
for f in "$p"/.*-plugin/plugin.json "$work/.kimi-plugin/plugin.json" "$work/.grok-plugin/plugin.json"; do
  grep -q '"version": "9.9.9"' "$f" || { stamped=0; echo "        not stamped: ${f#"$work"/}"; }
done
grep -q '^version: 9.9.9$' "$p/plugin.yaml" || { stamped=0; echo "        not stamped: plugin.yaml"; }
[ "$stamped" = 1 ] && ok "versions stamped from package.json" || bad "versions not stamped"

echo "tampered" >> "$p/skills/sample-skill/SKILL.md"
expect_fail "hand edit inside the bundle is drift" "sample-skill/SKILL.md differs" scripts/sync-plugins.sh --check
run scripts/sync-plugins.sh
echo "stray" > "$p/skills/sample-skill/stray.md"
expect_fail "file with no canonical source is drift" "stray.md has no canonical source" scripts/sync-plugins.sh --check
expect_fail "validate.sh fails on drift" "plugins/ is out of sync" scripts/validate.sh
rm -f "$p/skills/sample-skill/stray.md"
echo " " >> "$work/.kimi-plugin/plugin.json"
expect_fail "hand edit of a root manifest is drift" "kimi-plugin/plugin.json differs" scripts/sync-plugins.sh --check
rm -f "$work/.grok-plugin/marketplace.json"
expect_fail "missing root manifest is drift" "grok-plugin/marketplace.json differs" scripts/sync-plugins.sh --check
expect_ok "sync restores the root manifests" scripts/sync-plugins.sh
expect_ok "restored root manifests are in sync" scripts/sync-plugins.sh --check
echo "# Agent rules" > "$p/AGENTS.md"
mkdir -p "$p/rules" && echo "# Rule" > "$p/rules/rule.md"
expect_fail "instruction and rule files in a bundle fail" "AGENTS.md: plugin bundles must not ship instruction or rule files" scripts/validate.sh
expect_fail "rule folders in a bundle fail" "rules: plugin bundles must not ship instruction or rule files" scripts/validate.sh
rm -rf "$p/AGENTS.md" "$p/rules"

mkdir -p "$work/skills/games/sample-game"
skill skills/games/sample-game sample-game "Game."
expect_fail "unregistered pack is refused" "no metadata|not registered" scripts/sync-plugins.sh
rm -rf "$work/skills/games"

if command -v python3 >/dev/null 2>&1; then
  skill skills/games/sample-game sample-game "Game."
  python3 - "$work" <<'PY'
import json, sys
work = sys.argv[1]
desc = "Sample games pack."
with open(work + "/scripts/sync-plugins.sh") as f:
    s = f.read()
case = ('    games)\n      display_name="Games Skills"\n      description="%s"\n'
        '      short_description="Games"\n      long_description="Games."\n'
        '      keywords=(skills games)\n      default_prompts=("Play.")\n      ;;\n' % desc)
s = s.replace("    *) return 1 ;;\n", case + "    *) return 1 ;;\n", 1)
with open(work + "/scripts/sync-plugins.sh", "w") as f:
    f.write(s)
for path, entry in ((".claude-plugin/marketplace.json",
                     {"name": "games-skills", "description": desc, "source": "./plugins/games-skills", "version": "9.9.9"}),
                    (".agents/plugins/marketplace.json",
                     {"name": "games-skills", "source": {"source": "local", "path": "./plugins/games-skills"},
                      "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Coding"})):
    with open(f"{work}/{path}") as f:
        m = json.load(f)
    m["plugins"].append(entry)
    with open(f"{work}/{path}", "w") as f:
        json.dump(m, f, indent=2)
        f.write("\n")
PY
  expect_ok "a registered second pack syncs" scripts/sync-plugins.sh
  g="$work/plugins/games-skills"
  [ -f "$g/skills/sample-game/SKILL.md" ] && [ -f "$g/.kimi-plugin/plugin.json" ] && [ -f "$g/index.js" ] &&
    grep -q '"./plugins/engineering-skills/skills/"' "$work/.kimi-plugin/plugin.json" &&
    grep -q '"name": "games-skills"' "$work/.grok-plugin/marketplace.json" &&
    ok "a second pack gets its own bundle; root entry points keep the root pack" ||
    bad "second pack bundle or root entry points wrong"
fi

mkdir -p "$work/plugins/orphan-skills" && echo '{}' > "$work/plugins/orphan-skills/x.json"
expect_fail "orphan bundle is refused" "orphan-skills/ has no canonical pack" scripts/sync-plugins.sh --check
rm -rf "$work/plugins/orphan-skills"

fresh
sed -i.bak 's|"./plugins/engineering-skills/skills"|"./plugins/other-skills/skills"|' "$work/package.json" && rm -f "$work/package.json.bak"
expect_fail "package.json must list the root pack for pi" 'the "pi" skills list must name' scripts/sync-plugins.sh --check

fresh
sed -i.bak 's|./plugins/engineering-skills/index.js|./plugins/other-skills/index.js|' "$work/index.js" && rm -f "$work/index.js.bak"
expect_fail "index.js must load the root pack" "index.js must load ./plugins/engineering-skills/index.js" scripts/sync-plugins.sh --check

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
