#!/usr/bin/env bash
# Normalized entry to the hook checks, independent of any harness.
# Usage: check.sh --hook guard-destructive-git|guard-protected-branch
#                 --tool shell|edit [--command CMD] [--file-path PATH]...
#                 [--cwd DIR] [--event EVENT]
# Exit status: 0 allow, 2 deny (reason on stderr), 64 usage error.
case "${BASH_SOURCE[0]}" in */*) AUG_LIB="${BASH_SOURCE[0]%/*}" ;; *) AUG_LIB=. ;; esac
# shellcheck source=adapter.sh
. "$AUG_LIB/adapter.sh"

usage() { sed -n '3,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 64; }

hook="" tool="" event="PreToolUse"
AUG_COMMAND="" AUG_PATHS=() AUG_CWD="$PWD"
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --hook) hook="$2" ;;
    --tool) tool="$2" ;;
    --command) AUG_COMMAND="$2" ;;
    --file-path) AUG_PATHS[${#AUG_PATHS[@]}]="$2" ;;
    --cwd) AUG_CWD="$2" ;;
    --event) event="$2" ;;
    *) usage ;;
  esac
  shift 2
done
case "$hook" in guard-destructive-git|guard-protected-branch) ;; *) usage ;; esac
case "$tool" in shell|edit) ;; *) usage ;; esac
[ "$event" = PreToolUse ] || exit 0
aug_set_cwd "$AUG_CWD" "$PWD" || usage
aug_run_checks "$hook" "$tool" && exit 0
echo "$hook blocked this: $AUG_REASON" >&2
exit 2
