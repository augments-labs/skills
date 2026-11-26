#!/usr/bin/env bash
# Structural, token-budget, trigger-collision, and plugin-sync validator for
# augments-labs/skills. Portable across Linux, macOS, and Windows Git Bash.
set -euo pipefail
export LC_ALL=C

strict=0
mode="check"
for arg in "$@"; do
  case "$arg" in
    --strict) strict=1 ;;
    --table) mode="table" ;;
    --help|-h)
      echo "Usage: bash scripts/validate.sh [--strict | --table]"
      exit 0
      ;;
    *)
      echo "validate.sh: unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

AUTO_DESC_MAX_CHARS=3400
USER_DESC_MAX_CHARS=2400
COMBINED_DESC_MAX_CHARS=5800
BODY_MAX_TOKENS=2000

errors=0
fail() { echo "FAIL: $*" >&2; errors=$((errors + 1)); }
warn() {
  if [ "$strict" -eq 1 ]; then
    fail "$*"
  else
    echo "WARN: $*" >&2
  fi
}

# Compute engineering pack token-budget table (used by both --table and check mode).
eng_auto_chars=0 eng_user_chars=0 eng_auto_count=0 eng_user_count=0 eng_total_words=0 eng_total_bytes=0

compute_budgets() {
  local pack_dir pack auto_chars user_chars auto_count user_count total_words total_bytes
  local skill_file fm_end is_manual desc_text w b t combined_chars
  for pack_dir in skills/*; do
    [ -d "$pack_dir" ] || continue
    pack=$(basename "$pack_dir")
    case "$pack" in in-progress|deprecated) continue ;; esac
    auto_chars=0 user_chars=0 auto_count=0 user_count=0 total_words=0 total_bytes=0
    for skill_file in "$pack_dir"/*/SKILL.md; do
      [ -f "$skill_file" ] || continue
      fm_end=$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {print NR; exit}' "$skill_file")
      [ -n "$fm_end" ] || continue
      is_manual=0
      if awk -v e="$fm_end" 'NR>1 && NR<e && /^disable-model-invocation:[[:space:]]*true[[:space:]]*$/ {found=1} END {exit !found}' "$skill_file"; then
        is_manual=1
      fi
      desc_text=$(awk -v e="$fm_end" 'NR>1 && NR<e && /^description:/ {sub(/^description:[[:space:]]*/, ""); sub(/^"/, ""); sub(/"$/, ""); print; exit}' "$skill_file")
      if [ "$is_manual" -eq 1 ]; then
        user_count=$((user_count + 1))
        user_chars=$((user_chars + ${#desc_text}))
      else
        auto_count=$((auto_count + 1))
        auto_chars=$((auto_chars + ${#desc_text}))
      fi
      w=$(awk -v e="$fm_end" 'NR>e' "$skill_file" | wc -w | tr -d ' ')
      b=$(awk -v e="$fm_end" 'NR>e' "$skill_file" | wc -c | tr -d ' ')
      t=$(((b + 3) / 4))
      total_words=$((total_words + w))
      total_bytes=$((total_bytes + b))
      if [ "$mode" = "check" ] && [ "$t" -gt "$BODY_MAX_TOKENS" ]; then
        fail "$skill_file: body approx $t tokens exceeds $BODY_MAX_TOKENS"
      fi
    done
    combined_chars=$((auto_chars + user_chars))
    if [ "$mode" = "check" ]; then
      [ "$auto_chars" -le "$AUTO_DESC_MAX_CHARS" ] || fail "pack '$pack' auto-triggered descriptions total $auto_chars chars (max $AUTO_DESC_MAX_CHARS)"
      [ "$user_chars" -le "$USER_DESC_MAX_CHARS" ] || fail "pack '$pack' user-invoked descriptions total $user_chars chars (max $USER_DESC_MAX_CHARS)"
      [ "$combined_chars" -le "$COMBINED_DESC_MAX_CHARS" ] || fail "pack '$pack' combined descriptions total $combined_chars chars (max $COMBINED_DESC_MAX_CHARS)"
    fi
    if [ "$pack" = "engineering" ]; then
      eng_auto_chars=$auto_chars; eng_user_chars=$user_chars
      eng_auto_count=$auto_count; eng_user_count=$user_count
      eng_total_words=$total_words; eng_total_bytes=$total_bytes
    fi
  done
}

render_table() {
  local total_skills=$((eng_auto_count + eng_user_count))
  local total_tokens=$(((eng_total_bytes + 3) / 4))
  echo "| Surface (\`engineering-skills\`) | Skills | Words | Approx tokens |"
  echo "| --- | --- | --- | --- |"
  if [ "$total_skills" -eq 0 ]; then
    echo "| Pre-release skeleton (no promoted skills yet) | 0 | 0 | 0 |"
  else
    echo "| Auto-triggered descriptions ($eng_auto_chars chars) | $eng_auto_count | n/a | $(((eng_auto_chars + 3) / 4)) |"
    echo "| User-invoked descriptions ($eng_user_chars chars) | $eng_user_count | n/a | $(((eng_user_chars + 3) / 4)) |"
    echo "| Promoted skill bodies (if all loaded) | $total_skills | $eng_total_words | $total_tokens |"
  fi
}

if [ "$mode" = "table" ]; then
  compute_budgets
  render_table
  exit 0
fi

# 1. Required root files.
for f in README.md AGENTS.md CONTRIBUTING.md RELEASING.md CHANGELOG.md SECURITY.md package.json index.js .claude-plugin/marketplace.json .agents/plugins/marketplace.json; do
  [ -f "$f" ] || fail "missing required file: $f"
done
for f in CLAUDE.md GEMINI.md; do
  [ -e "$f" ] || fail "missing required file/symlink: $f"
done

# 2. JSON and YAML syntax checks.
check_json_file() {
  local f="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" || fail "$f: invalid JSON"
  elif command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$f" || fail "$f: invalid JSON"
  fi
}

root_manifests=".kimi-plugin/plugin.json .grok-plugin/plugin.json .grok-plugin/marketplace.json"
for jf in package.json .claude-plugin/marketplace.json .agents/plugins/marketplace.json $root_manifests; do
  [ -f "$jf" ] && check_json_file "$jf"
done

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  for yf in .github/workflows/*.yml .github/ISSUE_TEMPLATE/*.yml; do
    [ -f "$yf" ] || continue
    python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$yf" || fail "$yf: invalid YAML"
  done
fi

# 3. Claude Code marketplace schema guard: owner must not carry "url".
if [ -f .claude-plugin/marketplace.json ]; then
  if awk '/"owner"[[:space:]]*:/,/}/ { if ($0 ~ /"url"[[:space:]]*:/) found=1 } END { exit !found }' .claude-plugin/marketplace.json; then
    fail ".claude-plugin/marketplace.json: owner.url is rejected by strict marketplace schema"
  fi
fi

# 4. Canonical version parity across package.json, marketplace.json, and plugin manifests.
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

# 4b. Plugin bundles must not ship instruction or rule files at their root.
if [ -d plugins ]; then
  while IFS= read -r rf; do
    fail "$rf: plugin bundles must not ship instruction or rule files"
  done < <(find plugins -mindepth 2 -maxdepth 2 \( -iname 'AGENTS.md' -o -iname 'AGENT.md' -o -iname 'AGENTS.local.md' \
    -o -iname 'CLAUDE.md' -o -iname 'GEMINI.md' -o -name '.windsurfrules' -o -name '.cursorrules' -o -name 'rules' \) 2>/dev/null | sort)
fi

# 5. Promoted skill validation (frontmatter, names, size ceilings, forbidden patterns).
SHADOWED_COMMANDS=" review simplify help clear compact plan init config status doctor login logout mcp model memory permissions plugin plugins skills resume rename cost context export fast effort vim bug diff exit quit "

promoted_count=0
for skill_file in skills/*/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  case "$skill_file" in skills/in-progress/*|skills/deprecated/*) continue ;; esac
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

  if awk -v e="$fm_end" 'NR>1 && NR<e && /^hooks:/ {found=1} END {exit !found}' "$skill_file"; then
    fail "$skill_file: inline hooks in SKILL.md frontmatter are forbidden; use hooks/<pack>/"
  fi

  body_lines=$(awk -v e="$fm_end" 'NR>e' "$skill_file" | wc -l | tr -d ' ')
  body_bytes=$(awk -v e="$fm_end" 'NR>e' "$skill_file" | wc -c | tr -d ' ')
  [ "$body_lines" -le 200 ] || fail "$skill_file: body has $body_lines lines (max 200)"
  [ "$body_bytes" -le 8000 ] || fail "$skill_file: body has $body_bytes bytes (max 8000)"
  if [ "$body_lines" -gt 160 ]; then
    warn "$skill_file: body has $body_lines lines (target <= 160)"
  fi

  while IFS= read -r md; do
    [ -f "$md" ] || continue
    grep -q '\.sdlc-skills/' "$md" && fail "$md: forbidden .sdlc-skills/ metadata path"
    grep -qE '<EXTREMELY-IMPORTANT>|<EXTREMELY_IMPORTANT>' "$md" && fail "$md: forbidden shouting banner"
    grep -qE '(^|[^a-zA-Z0-9_-])docs/[a-zA-Z0-9_./-]+\.md' "$md" && fail "$md: skills must not reference docs/ paths"
  done < <(find "$skill_dir" -maxdepth 2 -name '*.md' -type f | sort)

  while IFS= read -r ref_line; do
    [ -n "$ref_line" ] || continue
    if ! printf '%s\n' "$ref_line" | grep -qiE '\b(when|if|before|after)\b'; then
      warn "$skill_file: support-file mention lacks a load condition (when/if/before/after): $ref_line"
    fi
  done < <(awk -v e="$fm_end" 'NR>e && /(references|assets)\/[A-Za-z0-9._-]+\.md/' "$skill_file")
done

# 6. No forbidden .sdlc-skills/ markers in docs/ or hooks/.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -q '\.sdlc-skills/' "$f" && fail "$f: forbidden .sdlc-skills/ reference"
done < <(find docs hooks -type f \( -name '*.md' -o -name '*.sh' \) 2>/dev/null | sort)

# 7. Dangling references across promoted and in-progress skills.
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
      case "$target" in http://*|https://*|mailto:*|\#*) continue ;; esac
      target=${target%%#*}
      if [ "$md" = "$skill_file" ]; then
        case "$target" in
          ../../*) fail "$md: link '$target' leaves the pack" ;;
          ../*)
            ref=${target#../}; ref=${ref%%/*}
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

# 8. Per-pack token budgets and README token-budget-table synchronization.
compute_budgets
if [ -f README.md ] && grep -q '^<!-- token-budget-table:start -->$' README.md && grep -q '^<!-- token-budget-table:end -->$' README.md; then
  readme_table=$(sed -n '/^<!-- token-budget-table:start -->$/,/^<!-- token-budget-table:end -->$/p' README.md | sed '1d;$d')
  expected_table=$(render_table)
  if [ "$readme_table" != "$expected_table" ]; then
    fail "README.md token-budget-table is out of sync with scripts/validate.sh --table"
  fi
fi

# 9. Cross-skill trigger phrase collisions within each pack.
if [ "$promoted_count" -ge 2 ]; then
  trig_tmp=$(mktemp)
  trap 'rm -f "$trig_tmp"' EXIT
  for skill_file in skills/*/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    case "$skill_file" in skills/in-progress/*|skills/deprecated/*) continue ;; esac
    skill_dir=$(dirname "$skill_file")
    pack=$(basename "$(dirname "$skill_dir")")
    name=$(basename "$skill_dir")
    desc=$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {exit} fm && /^description:/ {sub(/^description:[[:space:]]*"?/, ""); sub(/"$/, ""); print; exit}' "$skill_file")
    printf '%s\n' "$desc" \
      | sed -nE 's/.*([Uu]se when|[Uu]se before|[Ii]nvoke only when)[[:space:]]+(.*)/\2/p' \
      | sed -E 's/\.[[:space:]]*[Ss]kip.*$//; s/[.!?]+$//' \
      | tr 'A-Z' 'a-z' | tr ',;' '\n' \
      | sed -E 's/^[[:space:]]+(or|and)[[:space:]]+//; s/^(or|and)[[:space:]]+//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[.!?]+$//' \
      | awk -v p="$pack" -v s="$name" 'NF >= 2 { print p "\t" $0 "\t" s }' >> "$trig_tmp"
  done
  collisions=$(sort "$trig_tmp" | awk -F'\t' '
    prev_pack == $1 && prev_clause == $2 && prev_skill != $3 {
      print "exact trigger collision in pack \"" $1 "\" on \"" $2 "\": " prev_skill " vs " $3
      found=1
    }
    { prev_pack=$1; prev_clause=$2; prev_skill=$3 }
    END { exit !found }
  ' || true)
  if [ -n "$collisions" ]; then
    while IFS= read -r c; do
      [ -n "$c" ] && warn "$c"
    done <<< "$collisions"
  fi
fi

# 10. Generated plugin bundles must match canonical sources with no unshipped leaks.
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

echo "ok: validate.sh passed (version $pkg_ver, $promoted_count promoted skill(s), auto $eng_auto_chars/$AUTO_DESC_MAX_CHARS chars)."
