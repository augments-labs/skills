#!/usr/bin/env bash
# Structural and policy validator for augments-labs/skills.
# Portable across Linux, macOS, and Windows Git Bash (no third-party deps).
set -euo pipefail
export LC_ALL=C

strict=0
for arg in "$@"; do
  case "$arg" in
    --strict) strict=1 ;;
    --help|-h)
      echo "Usage: bash scripts/validate.sh [--strict]"
      exit 0
      ;;
    *)
      echo "validate.sh: unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

errors=0
fail() { echo "FAIL: $*" >&2; errors=$((errors + 1)); }
warn() {
  if [ "$strict" -eq 1 ]; then
    fail "$*"
  else
    echo "WARN: $*" >&2
  fi
}

# 1. Verify required root files exist (including CLAUDE.md and GEMINI.md symlinks/files).
for f in README.md AGENTS.md CONTRIBUTING.md RELEASING.md CHANGELOG.md CODE_OF_CONDUCT.md SECURITY.md package.json index.js .claude-plugin/marketplace.json .agents/plugins/marketplace.json; do
  [ -f "$f" ] || fail "missing required file: $f"
done
for f in CLAUDE.md GEMINI.md; do
  [ -e "$f" ] || fail "missing required file/symlink: $f"
done

# 2. Verify JSON syntax (uses python3 or node when present).
check_json_file() {
  local f="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" \
      || fail "$f: invalid JSON"
  elif command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$f" \
      || fail "$f: invalid JSON"
  fi
}

# Root manifests that sync-plugins.sh writes for the root pack.
root_manifests=".kimi-plugin/plugin.json .grok-plugin/plugin.json .grok-plugin/marketplace.json"
for jf in package.json .claude-plugin/marketplace.json .agents/plugins/marketplace.json $root_manifests; do
  [ -f "$jf" ] && check_json_file "$jf"
done

# 2b. Verify GitHub workflow and issue-template YAML when PyYAML is available (zero mandatory deps).
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  for yf in .github/workflows/*.yml .github/ISSUE_TEMPLATE/*.yml; do
    [ -f "$yf" ] || continue
    python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$yf" \
      || fail "$yf: invalid YAML"
  done
fi

# 3. Claude Code marketplace schema guard: owner must not carry "url" (rejected by strict Zod parser).
if [ -f .claude-plugin/marketplace.json ]; then
  if awk '/"owner"[[:space:]]*:/,/}/ { if ($0 ~ /"url"[[:space:]]*:/) found=1 } END { exit !found }' .claude-plugin/marketplace.json; then
    fail ".claude-plugin/marketplace.json: owner.url is rejected by strict marketplace schema"
  fi
fi

# 4. Canonical version parity across package.json, marketplace.json, and any generated plugin manifests.
pkg_ver=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -n 1)
[ -n "$pkg_ver" ] || fail "package.json: missing version"
for vf in .claude-plugin/marketplace.json $root_manifests; do
  [ -f "$vf" ] || continue
  while IFS= read -r mv; do
    if [ -n "$mv" ] && [ "$mv" != "$pkg_ver" ]; then
      fail "$vf: version '$mv' disagrees with package.json '$pkg_ver'"
    fi
  done < <(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$vf")
done
if [ -d plugins ]; then
  while IFS= read -r pm; do
    [ -f "$pm" ] || continue
    case "$pm" in
      *.json)
        check_json_file "$pm"
        mv=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pm" | head -n 1)
        ;;
      *.yaml|*.yml)
        mv=$(sed -nE 's/^version:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' "$pm" | head -n 1)
        ;;
      *) mv="" ;;
    esac
    if [ -n "$mv" ] && [ "$mv" != "$pkg_ver" ]; then
      fail "$pm: version '$mv' disagrees with package.json '$pkg_ver'"
    fi
  done < <(find plugins -maxdepth 3 \( -name 'plugin.json' -o -name 'plugin.yaml' -o -name 'package.json' \) -type f 2>/dev/null | sort)
fi

# 4b. Some harnesses load a plugin's agent-instruction and rule files as
# always-on rules. A bundle ships skills and hooks only.
if [ -d plugins ]; then
  while IFS= read -r rf; do
    fail "$rf: plugin bundles must not ship instruction or rule files"
  done < <(find plugins -mindepth 2 -maxdepth 2 \( -iname 'AGENTS.md' -o -iname 'AGENT.md' -o -iname 'AGENTS.local.md' \
    -o -iname 'CLAUDE.md' -o -iname 'GEMINI.md' -o -name '.windsurfrules' -o -name '.cursorrules' -o -name 'rules' \) 2>/dev/null | sort)
fi

# 5. Built-in harness slash commands that skills must never shadow.
SHADOWED_COMMANDS=" review simplify help clear compact plan init config status doctor login logout mcp model memory permissions plugin plugins skills resume rename cost context export fast effort vim bug diff exit quit "

# 6. Validate any promoted skills under skills/<pack>/<name>/SKILL.md.
promoted_count=0
for skill_file in skills/*/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  case "$skill_file" in
    skills/in-progress/*|skills/deprecated/*) continue ;;
  esac
  promoted_count=$((promoted_count + 1))

  skill_dir=$(dirname "$skill_file")
  dir_name=$(basename "$skill_dir")
  if ! printf '%s' "$dir_name" | grep -qE '^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$' || printf '%s' "$dir_name" | grep -q -- '--'; then
    fail "$skill_file: directory name '$dir_name' must be valid Agent Skills kebab-case (1-64 chars, no leading/trailing/double hyphens)"
  fi
  case "$SHADOWED_COMMANDS" in
    *" $dir_name "*) fail "$skill_file: skill name '$dir_name' shadows a built-in harness command" ;;
  esac

  fm_end=$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {print NR; exit}' "$skill_file")
  if [ -z "$fm_end" ]; then
    fail "$skill_file: missing YAML frontmatter"
    continue
  fi

  name_val=$(awk -v e="$fm_end" 'NR>1 && NR<e && /^name:/ {sub(/^name:[[:space:]]*/, ""); gsub(/^"|"$|^[[:space:]]+|[[:space:]]+$/, ""); print; exit}' "$skill_file")
  [ "$name_val" = "$dir_name" ] || fail "$skill_file: frontmatter name '$name_val' != directory '$dir_name'"

  desc_line=$(awk -v e="$fm_end" 'NR>1 && NR<e && /^description:/ {print; exit}' "$skill_file")
  if [ -z "$desc_line" ]; then
    fail "$skill_file: missing description in frontmatter"
  else
    case "$desc_line" in
      description:\ \"*\") ;;
      *) fail "$skill_file: description must be a double-quoted YAML string" ;;
    esac
    desc_text=$(printf '%s' "$desc_line" | sed 's/^description:[[:space:]]*//; s/^"//; s/"$//')
    desc_len=${#desc_text}
    if [ "$desc_len" -lt 1 ] || [ "$desc_len" -gt 1024 ]; then
      fail "$skill_file: description length $desc_len outside 1..1024"
    fi
  fi

  # Forbid inline hooks inside SKILL.md frontmatter (portable Agent Skills rule).
  if awk -v e="$fm_end" 'NR>1 && NR<e && /^hooks:/ {found=1} END {exit !found}' "$skill_file"; then
    fail "$skill_file: inline hooks in SKILL.md frontmatter are forbidden; use hooks/<pack>/"
  fi

  # Coherent house ceilings: <= 200 lines, <= 8,000 bytes, <= 2,000 approx tokens (bytes/4).
  body_lines=$(awk -v e="$fm_end" 'NR>e' "$skill_file" | wc -l | tr -d ' ')
  body_bytes=$(awk -v e="$fm_end" 'NR>e' "$skill_file" | wc -c | tr -d ' ')
  body_tokens=$(((body_bytes + 3) / 4))
  [ "$body_lines" -le 200 ] || fail "$skill_file: body has $body_lines lines (max 200)"
  [ "$body_bytes" -le 8000 ] || fail "$skill_file: body has $body_bytes bytes (max 8000)"
  [ "$body_tokens" -le 2000 ] || fail "$skill_file: body approx $body_tokens tokens (max 2000)"
  if [ "$body_lines" -gt 160 ]; then
    warn "$skill_file: body has $body_lines lines (target <= 160)"
  fi

  # Scan SKILL.md plus references/ and assets/ markdown files for forbidden patterns.
  while IFS= read -r md; do
    [ -f "$md" ] || continue
    if grep -q '\.sdlc-skills/' "$md"; then
      fail "$md: forbidden .sdlc-skills/ metadata path"
    fi
    if grep -qE '<EXTREMELY-IMPORTANT>|<EXTREMELY_IMPORTANT>' "$md"; then
      fail "$md: forbidden shouting banner"
    fi
    if grep -qE '(^|[^a-zA-Z0-9_-])docs/[a-zA-Z0-9_./-]+\.md' "$md"; then
      fail "$md: skills must not reference docs/ paths"
    fi
  done < <(find "$skill_dir" -maxdepth 2 -name '*.md' -type f | sort)

  # Every line in SKILL.md naming references/<f> or assets/<f> must state a load condition.
  while IFS= read -r ref_line; do
    [ -n "$ref_line" ] || continue
    if ! printf '%s\n' "$ref_line" | grep -qiE '\b(when|if|before|after)\b'; then
      warn "$skill_file: support-file mention lacks a load condition (when/if/before/after): $ref_line"
    fi
  done < <(awk -v e="$fm_end" 'NR>e && /(references|assets)\/[A-Za-z0-9._-]+\.md/' "$skill_file")
done

# 7. Ensure no forbidden markers leak into docs/ or hooks/.
for f in docs/*.md docs/*/*.md hooks/*/*.sh hooks/*/*/*.sh; do
  [ -f "$f" ] || continue
  if grep -q '\.sdlc-skills/' "$f"; then
    fail "$f: forbidden .sdlc-skills/ reference"
  fi
done

# 8. Dangling references: promoted and in-progress skills may name only
#    promoted skills, and only support files that exist inside the skill.
promoted_names=" "
for f in skills/*/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in skills/in-progress/*|skills/deprecated/*) continue ;; esac
  promoted_names="$promoted_names$(basename "$(dirname "$f")") "
done
for skill_file in skills/*/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  case "$skill_file" in skills/deprecated/*) continue ;; esac
  skill_dir=$(dirname "$skill_file")
  self=$(basename "$skill_dir")
  while IFS= read -r md; do
    if grep -qE 'skills/(in-progress|deprecated)/' "$md"; then
      fail "$md: names an unshipped skill path (skills/in-progress/ or skills/deprecated/)"
    fi
    while IFS= read -r ref; do
      [ -n "$ref" ] && [ "$ref" != "$self" ] || continue
      case "$promoted_names" in
        *" $ref "*) ;;
        *) fail "$md: names the '$ref' skill, which is not promoted" ;;
      esac
    done < <(grep -oE '`[a-z0-9][a-z0-9-]*` skill' "$md" | sed 's/^`//; s/` skill$//' | sort -u)
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      case "$target" in
        http://*|https://*|mailto:*|\#*) continue ;;
      esac
      target=${target%%#*}
      if [ "$md" = "$skill_file" ]; then
        case "$target" in
          ../../*) fail "$md: link '$target' leaves the pack" ;;
          ../*)
            ref=${target#../}
            ref=${ref%%/*}
            case "$promoted_names" in
              *" $ref "*) ;;
              *) fail "$md: links to the '$ref' skill, which is not promoted" ;;
            esac
            ;;
          *) [ -e "$skill_dir/$target" ] || fail "$md: link target '$target' does not exist" ;;
        esac
      else
        [ -e "$(dirname "$md")/$target" ] || fail "$md: link target '$target' does not exist"
      fi
    done < <(grep -oE '\]\([^) ]+\)' "$md" | sed 's/^](//; s/)$//' | sort -u)
    while IFS= read -r sf; do
      [ -n "$sf" ] || continue
      [ -e "$skill_dir/$sf" ] || fail "$md: names support file '$sf', which does not exist in $skill_dir/"
    done < <(grep -oE '(^|[^A-Za-z0-9_./-])(references|assets|scripts)/[A-Za-z0-9._-]+' "$md" |
      sed -E 's/^[^a-z]//; s/\.+$//' | sort -u)
  done < <(find "$skill_dir" -name '*.md' -type f | sort)
done

# 9. Generated plugin bundles must match their canonical sources, and no
#    staging, retired, or eval tree may ever enter one.
if [ -f scripts/sync-plugins.sh ]; then
  if ! sync_out=$(bash scripts/sync-plugins.sh --check 2>&1); then
    printf '%s\n' "$sync_out" | sed 's/^/  /' >&2
    fail "plugins/ is out of sync with skills/ and hooks/; run: bash scripts/sync-plugins.sh"
  fi
fi
if [ -d plugins ]; then
  while IFS= read -r leak; do
    [ -n "$leak" ] && fail "$leak: in-progress, deprecated, and eval trees never ship in plugins/"
  done < <(find plugins \( -path '*/in-progress/*' -o -path '*/deprecated/*' -o -path '*/evals/*' \) -type f 2>/dev/null | sort)
fi

if [ "$errors" -gt 0 ]; then
  echo "validate.sh: $errors error(s) found." >&2
  exit 1
fi

echo "ok: validate.sh passed (version $pkg_ver, $promoted_count promoted skill(s))."
