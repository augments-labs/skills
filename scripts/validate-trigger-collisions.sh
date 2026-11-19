#!/usr/bin/env bash
# Checks for overlapping multi-word trigger phrases across promoted skills within each pack.
set -euo pipefail
export LC_ALL=C

strict=0
for arg in "$@"; do
  case "$arg" in
    --strict) strict=1 ;;
    --help|-h)
      echo "Usage: bash scripts/validate-trigger-collisions.sh [--strict]"
      exit 0
      ;;
    *)
      echo "validate-trigger-collisions.sh: unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

count=0
for skill_file in skills/*/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  case "$skill_file" in
    skills/in-progress/*|skills/deprecated/*) continue ;;
  esac
  count=$((count + 1))
done

if [ "$count" -lt 2 ]; then
  echo "ok: validate-trigger-collisions.sh passed ($count promoted skill(s); nothing to collide)."
  exit 0
fi

# Extract normalized lowercase trigger clauses per pack from "Use when", "Use before",
# or "Invoke only when", strip trailing Skip clauses and punctuation, and check both
# exact clause collisions (error in --strict) and >= 3 shared content-word overlaps (warning).
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for skill_file in skills/*/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  case "$skill_file" in
    skills/in-progress/*|skills/deprecated/*) continue ;;
  esac
  skill_dir=$(dirname "$skill_file")
  pack=$(basename "$(dirname "$skill_dir")")
  name=$(basename "$skill_dir")
  desc=$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {exit} fm && /^description:/ {sub(/^description:[[:space:]]*"?/, ""); sub(/"$/, ""); print; exit}' "$skill_file")
  printf '%s\n' "$desc" \
    | sed -nE 's/.*([Uu]se when|[Uu]se before|[Ii]nvoke only when)[[:space:]]+(.*)/\2/p' \
    | sed -E 's/\.[[:space:]]*[Ss]kip.*$//; s/[.!?]+$//' \
    | tr 'A-Z' 'a-z' \
    | tr ',;' '\n' \
    | sed -E 's/^[[:space:]]+(or|and)[[:space:]]+//; s/^(or|and)[[:space:]]+//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[.!?]+$//' \
    | awk -v p="$pack" -v s="$name" 'NF >= 2 { print p "\t" $0 "\t" s }' >> "$tmp"
done

collisions=$(sort "$tmp" | awk -F'\t' '
  prev_pack == $1 && prev_clause == $2 && prev_skill != $3 {
    print "FAIL: exact trigger collision in pack \"" $1 "\" on \"" $2 "\": " prev_skill " vs " $3
    found=1
  }
  { prev_pack=$1; prev_clause=$2; prev_skill=$3 }
  END { exit !found }
' || true)

# Advisory content-word overlap scan within the same pack (>= 3 shared non-stopword tokens).
overlaps=$(awk -F'\t' '
  BEGIN {
    split("a an the to of in on for with by or and is are be as at it its this that your any when before only explicitly requested user", sw, " ")
    for (i in sw) stop[sw[i]] = 1
  }
  {
    key = $1 "/" $3
    pack_of[key] = $1
    skill_of[key] = $3
    skills[key] = 1
    n = split($2, toks, /[^a-z0-9-]+/)
    for (i = 1; i <= n; i++) {
      t = toks[i]
      if (length(t) >= 3 && !(t in stop)) words[key, t] = 1
    }
  }
  END {
    m = 0
    for (k in skills) { m++; ks[m] = k }
    for (i = 1; i <= m; i++) {
      for (j = i + 1; j <= m; j++) {
        a = ks[i]; b = ks[j]
        if (pack_of[a] != pack_of[b]) continue
        shared = 0; list = ""
        for (pair in words) {
          split(pair, parts, SUBSEP)
          if (parts[1] == a && ((b SUBSEP parts[2]) in words)) {
            shared++
            list = (list == "" ? parts[2] : list ", " parts[2])
          }
        }
        if (shared >= 3) {
          print "WARN: trigger token overlap in pack \"" pack_of[a] "\" (" shared " shared: " list "): " skill_of[a] " vs " skill_of[b]
        }
      }
    }
  }
' "$tmp" || true)

if [ -n "$overlaps" ]; then
  printf '%s\n' "$overlaps" >&2
fi

if [ -n "$collisions" ]; then
  printf '%s\n' "$collisions" >&2
  if [ "$strict" -eq 1 ]; then
    exit 1
  fi
fi

echo "ok: validate-trigger-collisions.sh passed ($count promoted skill(s))."
