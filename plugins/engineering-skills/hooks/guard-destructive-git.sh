#!/usr/bin/env bash
# guard-destructive-git: Blocks commands that destroy uncommitted work or rewrite history (reset --hard,
# forced pushes, clean -f, branch -D on unmerged work, rm -rf outside temporary
# and build directories) and commands that skip git hooks (--no-verify, HUSKY=0).
# Also blocks writes to ~/.config/augments-skills/, which only the user may change.
#
# Usage: guard-destructive-git.sh [claude-code|codex|antigravity] < hook-event.json
case "${BASH_SOURCE[0]}" in */*) AUG_LIB="${BASH_SOURCE[0]%/*}/lib" ;; *) AUG_LIB=lib ;; esac
# shellcheck source=lib/adapter.sh
. "$AUG_LIB/adapter.sh"
aug_hook_main guard-destructive-git "${1-}"
