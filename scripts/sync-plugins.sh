#!/usr/bin/env bash
# Rebuilds the generated plugin bundles under plugins/<pack>-skills/ from the
# canonical sources: promoted skills in skills/<pack>/<name>/ and hooks in
# hooks/<pack>/. Never copies skills/in-progress/, skills/deprecated/, or evals/.
# Portable across Linux, macOS, and Windows Git Bash (no third-party deps).
set -euo pipefail
export LC_ALL=C

# The pack that harnesses installing from the repository root load (pi from
# package.json, OpenCode from index.js, Kimi Code from .kimi-plugin/, Grok
# Build from .grok-plugin/). Every other pack installs from its own bundle
# path, which carries every manifest, or from a marketplace entry.
root_pack=engineering

usage() {
  cat <<EOF
Usage: bash scripts/sync-plugins.sh [--check]

Rebuilds plugins/<pack>-skills/ for every pack under skills/ or hooks/
(excluding skills/in-progress/ and skills/deprecated/):

  skills/<name>/                    promoted skills, flat (every harness + npx skills)
  hooks/                            hooks/<pack>/ minus config/ and tests/
  hooks/hooks.json                  Claude Code hooks  <- hooks/<pack>/config/claude-code.json
  hooks/codex-hooks.json            Codex CLI hooks    <- hooks/<pack>/config/codex.json
  hooks.json                        Antigravity hooks  <- hooks/<pack>/config/antigravity.json
  .claude-plugin/plugin.json        manifests, version stamped from package.json
  .codex-plugin/plugin.json
  .antigravity-plugin/plugin.json
  .cursor-plugin/plugin.json        skills only; "hooks": {} keeps hooks/hooks.json out
  .devin-plugin/plugin.json         skills; the hooks stay inert under Devin
  .grok-plugin/plugin.json          skills only; "hooks": [] keeps hook files out
  .kimi-plugin/plugin.json          skills only
  .muse-plugin/plugin.json          skills only, each skill listed
  plugin.yaml, __init__.py          Hermes Agent plugin  <- scripts/templates/hermes-init.py
  index.js                          OpenCode plugin      <- scripts/templates/opencode-index.js

The root pack ($root_pack) also installs from the repository root: this
script writes .kimi-plugin/plugin.json and .grok-plugin/plugin.json there,
copies .claude-plugin/marketplace.json to .grok-plugin/marketplace.json (Grok
Build reads only that index once .grok-plugin/ exists), and checks that
package.json ("pi" skills) and index.js (OpenCode) load the root pack's bundle.

  --check   build into a temporary directory and fail if plugins/ differs
  --help    this text

Exit codes: 0 in sync (or rebuilt) · 1 out of sync or invalid source · 2 bad arguments
EOF
}

mode=write
for arg in "$@"; do
  case "$arg" in
    --check) mode=check ;;
    -h|--help) usage; exit 0 ;;
    *) echo "sync-plugins.sh: unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() { echo "sync-plugins.sh: $*" >&2; exit 1; }

version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -n 1)
[ -n "$version" ] || die "package.json: missing version"

in_git=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=1

# Files under a directory that belong to the source tree: tracked or untracked
# but not ignored, so local caches and editor files never enter a bundle.
list_files() { # $1 directory
  [ -d "$1" ] || return 0
  if [ "$in_git" -eq 1 ]; then
    git ls-files -co --exclude-standard -- "$1" | while IFS= read -r f; do
      if [ -f "$f" ]; then printf '%s\n' "$f"; fi
    done | sort -u
  else
    find "$1" -type f | sort
  fi
}

json_escape() { # $1 string
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

json_array() { # items...
  local out="" item
  for item in "$@"; do
    [ -n "$out" ] && out="$out, "
    out="$out\"$(json_escape "$item")\""
  done
  printf '[%s]' "$out"
}

# Per-pack metadata. The description must match the pack's entry in
# .claude-plugin/marketplace.json; adding a pack means adding a case here.
pack_meta() { # $1 pack
  case "$1" in
    engineering)
      display_name="Engineering Skills"
      description="Engineering constraints, verification, production-safety skills, and deterministic hooks for coding agents."
      short_description="Eval-backed engineering skills and guardrail hooks"
      long_description="Focused, eval-backed skills for debugging, verification, and production-safe changes, plus deterministic hooks that block destructive git commands and direct writes to protected branches."
      keywords=(skills engineering debugging verification hooks guardrails)
      default_prompts=("Debug this failing test." "Verify this change before I merge it.")
      ;;
    *) return 1 ;;
  esac
}

# Packs: every directory under skills/ or hooks/ except the staging areas.
packs=()
for d in skills/*/ hooks/*/; do
  [ -d "$d" ] || continue
  p=$(basename "$d")
  case "$p" in in-progress|deprecated) continue ;; esac
  case " ${packs[*]-} " in *" $p "*) ;; *) packs+=("$p") ;; esac
done

build_pack() { # $1 pack, $2 output root
  local pack="$1" out="$2" plugin="$1-skills" dest f rel name
  local skill_names=() has_codex_hooks=0
  pack_meta "$pack" || die "pack '$pack' has no metadata in scripts/sync-plugins.sh (pack_meta)"
  grep -qF "\"source\": \"./plugins/$plugin\"" .claude-plugin/marketplace.json ||
    die "plugin '$plugin' is not registered in .claude-plugin/marketplace.json"
  grep -qF "\"path\": \"./plugins/$plugin\"" .agents/plugins/marketplace.json ||
    die "plugin '$plugin' is not registered in .agents/plugins/marketplace.json"
  grep -qF "\"description\": \"$(json_escape "$description")\"" .claude-plugin/marketplace.json ||
    die "plugin '$plugin' description in .claude-plugin/marketplace.json differs from pack_meta"

  dest="$out/$plugin"
  mkdir -p "$dest"

  # Promoted skills only: skills/<pack>/<name>/SKILL.md, copied flat.
  for f in skills/"$pack"/*/SKILL.md; do
    [ -f "$f" ] || continue
    name=$(basename "$(dirname "$f")")
    skill_names+=("$name")
    while IFS= read -r rel; do
      mkdir -p "$dest/skills/$(dirname "${rel#skills/"$pack"/}")"
      cp -p "$rel" "$dest/skills/${rel#skills/"$pack"/}"
    done < <(list_files "skills/$pack/$name")
  done

  # Hooks: scripts and libraries ship under hooks/; per-harness configs are
  # renamed to the path each harness reads; tests never ship.
  while IFS= read -r rel; do
    f=${rel#hooks/"$pack"/}
    case "$f" in
      tests/*|README.md) continue ;;
      config/claude-code.json) mkdir -p "$dest/hooks"; cp -p "$rel" "$dest/hooks/hooks.json" ;;
      config/codex.json) mkdir -p "$dest/hooks"; cp -p "$rel" "$dest/hooks/codex-hooks.json"; has_codex_hooks=1 ;;
      config/antigravity.json) cp -p "$rel" "$dest/hooks.json" ;;
      config/*) die "$rel: unknown hook config (expected claude-code.json, codex.json, or antigravity.json)" ;;
      *) mkdir -p "$dest/hooks/$(dirname "$f")"; cp -p "$rel" "$dest/hooks/$f" ;;
    esac
  done < <(list_files "hooks/$pack")

  local common
  common=$(manifest_common)

  # Claude Code discovers skills/ and hooks/hooks.json at the plugin root.
  mkdir -p "$dest/.claude-plugin"
  printf '{\n%s\n}\n' "$common" > "$dest/.claude-plugin/plugin.json"

  # Antigravity reads skills/ and hooks.json at the plugin root.
  mkdir -p "$dest/.antigravity-plugin"
  printf '{\n%s\n}\n' "$common" > "$dest/.antigravity-plugin/plugin.json"

  # Codex reads component paths from its manifest.
  local codex_paths=""
  [ "${#skill_names[@]}" -gt 0 ] && codex_paths="$codex_paths,
  \"skills\": \"./skills/\""
  [ "$has_codex_hooks" -eq 1 ] && codex_paths="$codex_paths,
  \"hooks\": \"./hooks/codex-hooks.json\""
  mkdir -p "$dest/.codex-plugin"
  cat > "$dest/.codex-plugin/plugin.json" <<EOF
{
$common$codex_paths,
  "interface": {
    "displayName": "$(json_escape "$display_name")",
    "shortDescription": "$(json_escape "$short_description")",
    "longDescription": "$(json_escape "$long_description")",
    "developerName": "Augments Labs",
    "category": "Coding",
    "capabilities": ["Interactive", "Read", "Write"],
    "websiteURL": "https://github.com/augments-labs/skills",
    "defaultPrompt": $(json_array "${default_prompts[@]}")
  }
}
EOF

  # Cursor falls back to hooks/hooks.json when its manifest names no hooks;
  # an empty object keeps the Claude Code hooks out of Cursor.
  local skills_path=""
  [ "${#skill_names[@]}" -gt 0 ] && skills_path=",
  \"skills\": \"./skills/\""
  mkdir -p "$dest/.cursor-plugin"
  printf '{\n%s%s,\n  "hooks": {}\n}\n' "$common" "$skills_path" > "$dest/.cursor-plugin/plugin.json"

  # Devin reads skills/ and also loads hooks/hooks.json and hooks.json, which
  # its manifest cannot turn off; the hook adapter stays inert under Devin.
  mkdir -p "$dest/.devin-plugin"
  printf '{\n%s\n}\n' "$common" > "$dest/.devin-plugin/plugin.json"

  # Grok Build loads hook files unless the manifest lists none.
  mkdir -p "$dest/.grok-plugin"
  printf '{\n%s%s,\n  "hooks": []\n}\n' "$common" "$skills_path" > "$dest/.grok-plugin/plugin.json"

  # Kimi Code reads component paths from its manifest.
  mkdir -p "$dest/.kimi-plugin"
  kimi_manifest "./skills/" > "$dest/.kimi-plugin/plugin.json"

  # Muse Code imports another family's manifest (and its hooks) unless its
  # own manifest names its directory and lists each skill.
  local muse_skills="" sep=""
  for name in ${skill_names[@]+"${skill_names[@]}"}; do
    muse_skills="$muse_skills$sep
      { \"id\": \"$name\", \"path\": \"skills/$name/SKILL.md\" }"
    sep=","
  done
  [ -n "$muse_skills" ] && muse_skills="$muse_skills
    "
  mkdir -p "$dest/.muse-plugin"
  cat > "$dest/.muse-plugin/plugin.json" <<EOF
{
  "schemaVersion": 1,
  "name": "$plugin",
  "version": "$version",
  "description": "$(json_escape "$description")",
  "compat": {
    "source": "native",
    "manifestDir": ".muse-plugin"
  },
  "capabilities": {
    "skills": [$muse_skills]
  }
}
EOF

  # Hermes Agent loads plugin.yaml and __init__.py from the plugin root.
  cat > "$dest/plugin.yaml" <<EOF
name: $plugin
version: $version
description: "$(json_escape "$description")"
EOF
  cp scripts/templates/hermes-init.py "$dest/__init__.py"

  # OpenCode loads index.js from a plugin directory or package.
  sed "s|@PLUGIN@|$plugin|g" scripts/templates/opencode-index.js > "$dest/index.js"
}

# manifest_common: the fields every JSON manifest of the current pack shares.
manifest_common() {
  cat <<EOF
  "name": "$plugin",
  "version": "$version",
  "description": "$(json_escape "$description")",
  "author": {
    "name": "Augments Labs"
  },
  "homepage": "https://github.com/augments-labs/skills",
  "repository": "https://github.com/augments-labs/skills",
  "license": "MIT",
  "keywords": $(json_array "${keywords[@]}")
EOF
}

# kimi_manifest SKILLS-PATH: the Kimi Code manifest for the current pack.
kimi_manifest() {
  cat <<EOF
{
  "name": "$plugin",
  "version": "$version",
  "description": "$(json_escape "$description")",
  "skills": ["$1"]
}
EOF
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for pack in ${packs[@]+"${packs[@]}"}; do
  build_pack "$pack" "$tmp"
done

# Repository-root entry points for the root pack.
[ -d "$tmp/$root_pack-skills" ] || die "root pack '$root_pack' has no bundle (expected skills/$root_pack/ or hooks/$root_pack/)"
grep -qF "\"./plugins/$root_pack-skills/skills\"" package.json ||
  die "package.json: the \"pi\" skills list must name ./plugins/$root_pack-skills/skills"
grep -qF "\"./plugins/$root_pack-skills/index.js\"" index.js ||
  die "index.js must load ./plugins/$root_pack-skills/index.js"
root_files=(.kimi-plugin/plugin.json .grok-plugin/plugin.json .grok-plugin/marketplace.json)
(
  plugin="$root_pack-skills"
  pack_meta "$root_pack"
  common=$(manifest_common)
  mkdir -p "$tmp/.root/.kimi-plugin" "$tmp/.root/.grok-plugin"
  kimi_manifest "./plugins/$plugin/skills/" > "$tmp/.root/.kimi-plugin/plugin.json"
  # Without it, Grok Build installs the repository root as a plugin of its
  # own and loads every SKILL.md under skills/, including skills/in-progress/.
  printf '{\n%s,\n  "skills": "./plugins/%s/skills/",\n  "hooks": []\n}\n' "$common" "$plugin" \
    > "$tmp/.root/.grok-plugin/plugin.json"
  cp .claude-plugin/marketplace.json "$tmp/.root/.grok-plugin/marketplace.json"
)

# Bundles on disk that no pack produces would ship stale content.
for d in plugins/*/; do
  [ -d "$d" ] || continue
  plugin=$(basename "$d")
  [ -d "$tmp/$plugin" ] || die "plugins/$plugin/ has no canonical pack (expected skills/${plugin%-skills}/ or hooks/${plugin%-skills}/)"
done

if [ "$mode" = check ]; then
  drift=0
  for d in "$tmp"/*/; do
    [ -d "$d" ] || continue
    plugin=$(basename "$d")
    expected=$(cd "$tmp/$plugin" && find . -type f | sed 's|^\./||' | sort)
    actual=$(list_files "plugins/$plugin" | sed "s|^plugins/$plugin/||" | sort)
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      echo "out of sync: plugins/$plugin/$f is missing" >&2; drift=1
    done < <(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      echo "out of sync: plugins/$plugin/$f has no canonical source" >&2; drift=1
    done < <(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      cmp -s "$tmp/$plugin/$f" "plugins/$plugin/$f" || {
        echo "out of sync: plugins/$plugin/$f differs from its canonical source" >&2; drift=1; }
    done < <(comm -12 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))
  done
  for f in "${root_files[@]}"; do
    cmp -s "$tmp/.root/$f" "$f" || {
      echo "out of sync: $f differs from its canonical source" >&2; drift=1; }
  done
  if [ "$drift" -ne 0 ]; then
    echo "sync-plugins.sh: plugins/ is out of sync; run: bash scripts/sync-plugins.sh" >&2
    exit 1
  fi
  echo "ok: plugins/ in sync (version $version, ${#packs[@]} pack(s))."
  exit 0
fi

for f in "${root_files[@]}"; do
  mkdir -p "$(dirname "$f")"
  cp "$tmp/.root/$f" "$f"
done
echo "synced ${root_files[*]} ($root_pack-skills, version $version)"

for d in "$tmp"/*/; do
  [ -d "$d" ] || continue
  plugin=$(basename "$d")
  rm -rf "plugins/$plugin"
  mkdir -p plugins
  cp -Rp "$tmp/$plugin" "plugins/$plugin"
  echo "synced plugins/$plugin (version $version)"
done
