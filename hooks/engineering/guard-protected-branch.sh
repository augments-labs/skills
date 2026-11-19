#!/usr/bin/env bash
# guard-protected-branch: Blocks commits, merges, pushes, and file edits on protected branches (main,
# master, and the repository's .augments-skills.json protectedBranches).
# Also blocks writes to ~/.config/augments-skills/, which only the user may change.
#
# Usage: guard-protected-branch.sh [claude-code|codex|antigravity] < hook-event.json
case "${BASH_SOURCE[0]}" in */*) AUG_LIB="${BASH_SOURCE[0]%/*}/lib" ;; *) AUG_LIB=lib ;; esac
# shellcheck source=lib/adapter.sh
. "$AUG_LIB/adapter.sh"
aug_hook_main guard-protected-branch "${1-}"
