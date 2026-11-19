# Shared helpers for the engineering hooks: JSON access, paths, policy.
# Sourced, never executed. Portable to bash 3.2 (macOS), BSD userland, and
# Git Bash on Windows: no associative arrays, no mapfile, no ${x,,}, no jq.
# Functions return values in REPLY to avoid subshells.

AUG_US=$'\037'
AUG_RS=$'\036'
AUG_NL=$'\n'
export LC_ALL=C

# The user-global directory that holds human-only bypasses. Agents may read
# it but never write it.
aug_guard_dir() {
  aug_normpath "${HOME:-/nonexistent}/.config/augments-skills"
}

# ---------------------------------------------------------------- JSON --

# aug_json_load "PATH PATH ..." < json
# Loads the leaf values at those exact paths, and the elements of arrays at
# those paths, into JK (path), JT (s or l), and JV (value). Returns 1 when the
# input is not valid JSON.
aug_json_load() {
  local out rec
  JK=() JT=() JV=()
  out="$(AUG_JMODE=multi AUG_JPATH="$1" awk -f "$AUG_LIB/json.awk")" || return 1
  while :; do
    case "$out" in *"$AUG_RS"*) ;; *) break ;; esac
    rec="${out%%"$AUG_RS"*}"
    out="${out#*"$AUG_RS"}"
    JK[${#JK[@]}]="${rec%%"$AUG_US"*}"
    rec="${rec#*"$AUG_US"}"
    JT[${#JT[@]}]="${rec%%"$AUG_US"*}"
    JV[${#JV[@]}]="${rec#*"$AUG_US"}"
  done
  return 0
}

# aug_jget PATH: REPLY = value at PATH; returns 1 when absent.
aug_jget() {
  local i=0
  REPLY=""
  while [ "$i" -lt "${#JK[@]}" ]; do
    if [ "${JK[$i]}" = "$1" ]; then REPLY="${JV[$i]}"; return 0; fi
    i=$((i + 1))
  done
  return 1
}

# aug_jarray PATH: AUG_ARR = string elements of the array at PATH, in order.
aug_jarray() {
  local i=0
  AUG_ARR=()
  while [ "$i" -lt "${#JK[@]}" ]; do
    case "${JK[$i]}" in
      "$1["*"]") [ "${JT[$i]}" = s ] && AUG_ARR[${#AUG_ARR[@]}]="${JV[$i]}" ;;
    esac
    i=$((i + 1))
  done
}

# aug_json_escape TEXT: REPLY = TEXT escaped for a JSON string.
aug_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  REPLY="$s"
}

# --------------------------------------------------------------- paths --

# aug_native_path P: REPLY = P with a Windows drive path (C:\x, C:/x) turned
# into the POSIX form Git Bash uses (/c/x).
aug_native_path() {
  REPLY="$1"
  case "$REPLY" in
    [A-Za-z]:[\\/]*|[A-Za-z]:)
      if command -v cygpath >/dev/null 2>&1; then
        REPLY="$(cygpath -u -- "$REPLY" 2>/dev/null)" || REPLY="$1"
      else
        REPLY="/${REPLY%%:*}${REPLY#?:}"
        REPLY="${REPLY//\\//}"
      fi
      ;;
  esac
}

# aug_normpath ABS: REPLY = ABS with ., .., and repeated slashes removed.
aug_normpath() {
  local rest="$1" seg out=""
  while [ -n "$rest" ]; do
    case "$rest" in
      */*) seg="${rest%%/*}"; rest="${rest#*/}" ;;
      *) seg="$rest"; rest="" ;;
    esac
    case "$seg" in
      ""|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  REPLY="${out:-/}"
}

# aug_abspath P BASE: REPLY = P made absolute against BASE and normalized.
# Expands a leading ~. BASE must be absolute.
aug_abspath() {
  local p
  aug_native_path "$1"; p="$REPLY"
  case "$p" in
    "~") p="${HOME:-/}" ;;
    "~/"*) p="${HOME:-}/${p#??}" ;;
  esac
  case "$p" in
    /*) ;;
    *) p="$2/$p" ;;
  esac
  aug_normpath "$p"
}

# aug_physpath ABS: REPLY = ABS with symlinks in its existing part resolved.
aug_physpath() {
  local dir="$1" tail="" phys
  while [ "$dir" != "/" ] && [ ! -d "$dir" ]; do
    tail="/${dir##*/}$tail"
    dir="${dir%/*}"
    [ -n "$dir" ] || dir="/"
  done
  phys="$(cd -P -- "$dir" 2>/dev/null && pwd -P)" || phys="$dir"
  aug_normpath "$phys$tail"
}

# aug_inside P ROOT: P is ROOT or below it (both normalized and absolute).
aug_inside() {
  [ "$1" = "$2" ] && return 0
  case "$1" in "${2%/}"/*) return 0 ;; esac
  return 1
}

# ---------------------------------------------------------------- policy --

# Reads $HOME/.config/augments-skills/policy.json. Missing or malformed
# policy means no bypass at all.
#   POL_DISABLED[]   hook names that do not run
#   POL_FWL          allow-unprotected (default) or block
#   POL_EXEMPT[]     repository paths where guard-protected-branch allows work
#   POL_PROTECTED[]  extra protected branch patterns
aug_policy_load() {
  local f="${HOME:-/nonexistent}/.config/augments-skills/policy.json"
  POL_DISABLED=() POL_EXEMPT=() POL_PROTECTED=() POL_FWL="allow-unprotected"
  [ -f "$f" ] || return 0
  if ! aug_json_load "disabledHooks forceWithLease protectedBranchExemptRepos protectedBranches" < "$f"; then
    echo "augments-skills hooks: ignoring malformed $f" >&2
    return 0
  fi
  aug_jarray disabledHooks; POL_DISABLED=(${AUG_ARR[@]+"${AUG_ARR[@]}"})
  aug_jarray protectedBranchExemptRepos; POL_EXEMPT=(${AUG_ARR[@]+"${AUG_ARR[@]}"})
  aug_jarray protectedBranches; POL_PROTECTED=(${AUG_ARR[@]+"${AUG_ARR[@]}"})
  aug_jget forceWithLease && [ "$REPLY" = block ] && POL_FWL=block
  return 0
}

aug_hook_disabled() {
  local h
  for h in ${POL_DISABLED[@]+"${POL_DISABLED[@]}"}; do
    [ "$h" = "$1" ] && return 0
  done
  return 1
}
