#!/usr/bin/env bash
# Context and token budget checker for augments-labs/skills.
# Enforces per-pack description budgets (auto, user-invoked, combined), per-skill
# body token ceiling, and README.md token-budget-table synchronization.
# Portable across Linux, macOS, and Windows Git Bash.
set -euo pipefail
export LC_ALL=C

mode="check"
for arg in "$@"; do
  case "$arg" in
    --check) mode="check" ;;
    --table) mode="table" ;;
    --help|-h)
      echo "Usage: bash scripts/token-budget.sh [--check | --table]"
      exit 0
      ;;
    *)
      echo "token-budget.sh: unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

AUTO_DESC_MAX_CHARS=3400
USER_DESC_MAX_CHARS=2400
COMBINED_DESC_MAX_CHARS=5800
BODY_MAX_TOKENS=2000

errors=0
eng_auto_chars=0
eng_user_chars=0
eng_auto_count=0
eng_user_count=0
eng_total_words=0
eng_total_bytes=0

for pack_dir in skills/*; do
  [ -d "$pack_dir" ] || continue
  pack=$(basename "$pack_dir")
  case "$pack" in
    in-progress|deprecated) continue ;;
  esac

  auto_chars=0
  user_chars=0
  auto_count=0
  user_count=0
  total_words=0
  total_bytes=0

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

    if [ "$t" -gt "$BODY_MAX_TOKENS" ]; then
      echo "FAIL: $skill_file body approx $t tokens exceeds $BODY_MAX_TOKENS" >&2
      errors=$((errors + 1))
    fi
  done

  combined_chars=$((auto_chars + user_chars))
  if [ "$auto_chars" -gt "$AUTO_DESC_MAX_CHARS" ]; then
    echo "FAIL: pack '$pack' auto-triggered descriptions total $auto_chars chars (max $AUTO_DESC_MAX_CHARS)" >&2
    errors=$((errors + 1))
  fi
  if [ "$user_chars" -gt "$USER_DESC_MAX_CHARS" ]; then
    echo "FAIL: pack '$pack' user-invoked descriptions total $user_chars chars (max $USER_DESC_MAX_CHARS)" >&2
    errors=$((errors + 1))
  fi
  if [ "$combined_chars" -gt "$COMBINED_DESC_MAX_CHARS" ]; then
    echo "FAIL: pack '$pack' combined descriptions total $combined_chars chars (max $COMBINED_DESC_MAX_CHARS)" >&2
    errors=$((errors + 1))
  fi

  if [ "$pack" = "engineering" ]; then
    eng_auto_chars=$auto_chars
    eng_user_chars=$user_chars
    eng_auto_count=$auto_count
    eng_user_count=$user_count
    eng_total_words=$total_words
    eng_total_bytes=$total_bytes
  fi
done

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
  render_table
  exit 0
fi

# Verify README.md token-budget-table matches rendered table.
if [ -f README.md ] && grep -q '^<!-- token-budget-table:start -->$' README.md && grep -q '^<!-- token-budget-table:end -->$' README.md; then
  readme_table=$(sed -n '/^<!-- token-budget-table:start -->$/,/^<!-- token-budget-table:end -->$/p' README.md | sed '1d;$d')
  expected_table=$(render_table)
  if [ "$readme_table" != "$expected_table" ]; then
    echo "FAIL: README.md token-budget-table is out of sync with scripts/token-budget.sh --table" >&2
    errors=$((errors + 1))
  fi
fi

if [ "$errors" -gt 0 ]; then
  exit 1
fi

echo "ok: token-budget.sh passed ($((eng_auto_count + eng_user_count)) promoted engineering skill(s), auto $eng_auto_chars/$AUTO_DESC_MAX_CHARS chars, user $eng_user_chars/$USER_DESC_MAX_CHARS chars)."
