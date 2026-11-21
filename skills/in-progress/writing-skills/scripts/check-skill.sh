#!/usr/bin/env bash
# Checks one Agent Skills directory: a frontmatter a strict loader accepts,
# a name matching the directory, a description within limits, a body within
# size, and support files that exist and are named from SKILL.md.
set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/check-skill.sh SKILL_DIR

Checks:
  SKILL.md exists and opens with a closed --- frontmatter block
  name         present, lowercase letters/digits/single hyphens, at most 64
               characters, equal to the directory name
  description  present, 1-1024 characters, and valid under a strict YAML
               loader: double- or single-quoted, a | or > block, or plain
               text with no ": " or " #" on any line and no leading
               indicator (* & [ { ! | > ' " % @ ` #)
  keys         only name, description, license, compatibility, metadata,
               allowed-tools at the top level (warn otherwise)
  body         at most 500 lines (warn past 200)
  support      every references/, scripts/, or assets/ path named in
               SKILL.md exists; every file in those folders is named in
               SKILL.md; a line naming a references/ or assets/ file says
               when to read it (when, if, before, after; warn otherwise);
               support files do not name other support files (warn)

Output: one "FAIL: ..." or "WARN: ..." line per finding.
Exit codes: 0 no FAIL, 1 one or more FAIL, 2 bad arguments.
USAGE
}

[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && { usage; exit 0; }
[ "$#" -eq 1 ] && [ -d "$1" ] || { usage >&2; exit 2; }
dir="${1%/}"
skill="$dir/SKILL.md"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
warn() { echo "WARN: $*"; }

[ -f "$skill" ] || { fail "no SKILL.md in $dir (the file name is case-sensitive)"; exit 1; }
[ "$(head -n1 "$skill" | tr -d '\r')" = "---" ] || { fail "SKILL.md does not start with a --- frontmatter line"; exit 1; }
end=$(awk 'NR > 1 && /^---[[:space:]]*$/ { print NR; exit }' "$skill")
[ -n "$end" ] || { fail "frontmatter is never closed with ---"; exit 1; }
front=$(sed -n "2,$((end - 1))p" "$skill" | tr -d '\r')

# The raw value of a top-level key, continuation lines joined with spaces.
raw() {
  printf '%s\n' "$front" | awk -v k="$1" '
    $0 ~ "^" k ":" { v = substr($0, length(k) + 2); on = 1; next }
    on && /^[[:space:]]/ { sub(/^[[:space:]]+/, ""); if ($0 != "") v = v " " $0; next }
    on { exit }
    END { sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); printf "%s", v }'
}
# The continuation lines of a top-level key, one per line.
cont() {
  printf '%s\n' "$front" | awk -v k="$1" '
    $0 ~ "^" k ":" { on = 1; next } on && /^[[:space:]]/ { print; next } on { exit }'
}

printf '%s\n' "$front" | grep -E '^[A-Za-z_][A-Za-z0-9_-]*:' | cut -d: -f1 | while read -r key; do
  case "$key" in name|description|license|compatibility|metadata|allowed-tools) ;;
    *) warn "frontmatter key '$key' is not a standard field";; esac
done

name=$(raw name); name="${name#\"}"; name="${name%\"}"; name="${name#\'}"; name="${name%\'}"
base=$(basename "$(cd "$dir" && pwd)")
if [ -z "$name" ]; then fail "name is missing"
elif ! printf '%s' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || [ "${#name}" -gt 64 ]; then
  fail "name '$name' must be lowercase letters, digits, and single hyphens, at most 64 characters"
elif [ "$name" != "$base" ]; then fail "name '$name' does not match the directory '$base'"; fi

desc=$(raw description)
first=$(printf '%s\n' "$front" | grep -m1 '^description:' | sed 's/^description:[[:space:]]*//')
text="$desc"
case "$first" in
  '') [ -n "$desc" ] || fail "description is missing";;
  \"*) [ "${desc: -1}" = '"' ] && [ "${#desc}" -ge 2 ] || fail "description opens a \" quote it never closes"
       text="${desc:1:${#desc}-2}";;
  \'*) [ "${desc: -1}" = "'" ] && [ "${#desc}" -ge 2 ] || fail "description opens a ' quote it never closes"
       text="${desc:1:${#desc}-2}";;
  \|*|\>*) text=$(cont description | sed 's/^[[:space:]]*//' | tr '\n' ' ');;
  *) if printf '%s' "$first" | grep -q '^[][*&{}!|>%@`#,?:-]'; then
       fail "unquoted description starts with a YAML indicator; quote it"
     fi
     if { printf '%s\n' "$first"; cont description; } | grep -Eq ': |:$| #'; then
       fail "unquoted description contains ': ' or ' #' (a strict YAML loader rejects or truncates it); quote it"
     fi;;
esac
text=$(printf '%s' "$text" | sed 's/[[:space:]]*$//')
[ "${#text}" -le 1024 ] || fail "description is ${#text} characters (limit 1024)"
[ -n "$desc" ] && [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ] && fail "description is empty"

body=$(tail -n +"$((end + 1))" "$skill")
lines=$(printf '%s\n' "$body" | wc -l)
if [ "$lines" -gt 500 ]; then fail "body is $lines lines (limit 500)"
elif [ "$lines" -gt 200 ]; then warn "body is $lines lines; past 200 it should justify itself"; fi

printf '%s\n' "$body" | grep -oE '(^|[[:space:]`("[])(\./)?(references|scripts|assets)/[A-Za-z0-9_./-]*[A-Za-z0-9_]' |
  sed -E 's#^[[:space:]`("[]?(\./)?##' | sort -u |
  while read -r ref; do [ -e "$dir/$ref" ] || echo "FAIL: SKILL.md names $ref, which does not exist"; done > "${TMPDIR:-/tmp}/check-skill.$$"
if [ -s "${TMPDIR:-/tmp}/check-skill.$$" ]; then
  cat "${TMPDIR:-/tmp}/check-skill.$$"; fails=$((fails + $(wc -l < "${TMPDIR:-/tmp}/check-skill.$$")))
fi
rm -f "${TMPDIR:-/tmp}/check-skill.$$"

for sub in references scripts assets; do
  [ -d "$dir/$sub" ] || continue
  while IFS= read -r f; do
    rel="${f#"$dir"/}"
    if ! printf '%s\n' "$body" | grep -qF "$rel"; then
      fail "$rel is never named in SKILL.md, so no agent will read or run it"
    elif [ "$sub" != scripts ] && ! printf '%s\n' "$body" | grep -F "$rel" | grep -Eiq '\b(when|if|before|after)\b'; then
      warn "$rel is named without a load condition (when, if, before, after)"
    fi
    if [ "$sub" != scripts ] && grep -Eq '(references|assets)/[A-Za-z0-9_-]' "$f"; then
      warn "$rel names another support file; keep support files one level deep"
    fi
  done < <(find "$dir/$sub" -type f | sort)
done

[ "$fails" -eq 0 ] && echo "ok: $dir"
[ "$fails" -eq 0 ]
