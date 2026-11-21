#!/usr/bin/env bash
# Points core.hooksPath at the tracked scripts/git-hooks/ directory so the
# optional pre-commit hook runs the CI checks locally. No third-party tool.
# --remove restores whatever core.hooksPath held before install.
set -uo pipefail

# Recorded when core.hooksPath was unset before install; never a real path.
PREV_MARKER='__augments-skills-hooks-unset__'
HOOKS_DIR=scripts/git-hooks

usage() {
  cat <<'EOF'
Usage: bash scripts/install-git-hooks.sh [--remove]

Points core.hooksPath at scripts/git-hooks/, whose pre-commit hook runs the
same checks as CI when a staged path can affect them and refuses .plans/ and
evals/workspaces/. Run it from the repository root.

  --remove  restore core.hooksPath to its value before install (or unset it)
  --help    this text

Exit codes: 0 installed or removed · 1 git config or the tracked hook failed
            2 not run from this repository's root, or a bad argument
EOF
}

[ $# -le 1 ] || { echo "at most one argument (see --help)" >&2; exit 2; }
mode=install
case "${1-}" in
  -h|--help) usage; exit 0 ;;
  --remove) mode=remove ;;
  "") ;;
  *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 2; }
toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not inside a git working tree" >&2; exit 2; }
here="$(pwd -P)"
top="$(cd "$toplevel" && pwd -P)"
[ "$here" = "$top" ] || { echo "run this from the repository root ($toplevel)" >&2; exit 2; }

# In a linked worktree .git is a pointer file; the record lives beside the
# shared git directory, where core.hooksPath itself is stored.
common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || { echo "could not resolve the git directory" >&2; exit 1; }
case "$common_dir" in /*) ;; *) common_dir="$top/$common_dir" ;; esac
prev_file="$common_dir/augments-skills-hooks.previous"

if [ "$mode" = remove ]; then
  if [ -f "$prev_file" ]; then
    prev="$(cat "$prev_file")"
    if [ "$prev" = "$PREV_MARKER" ]; then
      git config --unset core.hooksPath 2>/dev/null
    else
      git config core.hooksPath "$prev" || { echo "could not restore core.hooksPath" >&2; exit 1; }
    fi
    rm -f "$prev_file"
  elif [ "$(git config --get core.hooksPath 2>/dev/null || true)" = "$HOOKS_DIR" ]; then
    git config --unset core.hooksPath 2>/dev/null
  fi
  echo "removed: core.hooksPath restored"
  exit 0
fi

[ -f "$HOOKS_DIR/pre-commit" ] || { echo "missing $HOOKS_DIR/pre-commit" >&2; exit 1; }
if [ ! -f "$prev_file" ]; then
  current="$(git config --get core.hooksPath 2>/dev/null || true)"
  printf '%s' "${current:-$PREV_MARKER}" > "$prev_file" || { echo "could not save the previous core.hooksPath" >&2; exit 1; }
fi
git config core.hooksPath "$HOOKS_DIR" || { echo "could not set core.hooksPath" >&2; exit 1; }
echo "installed: core.hooksPath -> $HOOKS_DIR"
