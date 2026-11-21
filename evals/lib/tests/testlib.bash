#!/usr/bin/env bash
# Shared helpers for the offline eval suites. Sourced by evals/lib/tests/*.sh.
#
# Each suite gets a scratch directory (removed on exit), a throwaway operator
# home, credential seed, workspace root, and TMPDIR, and a PATH whose first
# entry is a copy of the tripwire shims, so a real agent CLI can never run.
set -uo pipefail
export LC_ALL=C

TL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
TL_EVALS="$TL_ROOT/evals"
TL_TESTS="$TL_EVALS/lib/tests"
TL_FIX="$TL_TESTS/fixtures"
TL_NAME="$(basename "${BASH_SOURCE[1]:-$0}" .sh)"

TL_TMP="$(mktemp -d "${TMPDIR:-/tmp}/evals-$TL_NAME.XXXXXX")"
TL_TMP="$(cd "$TL_TMP" && pwd -P)"
tl_cleanup() { chmod -R u+w "$TL_TMP" 2>/dev/null; rm -rf "$TL_TMP"; }
trap tl_cleanup EXIT

TL_TRIP="$TL_TMP/tripwire"
mkdir -p "$TL_TRIP" "$TL_TMP/tmp" "$TL_TMP/operator" "$TL_TMP/seed" "$TL_TMP/ws"
cp "$TL_TESTS/tripwire/"* "$TL_TRIP/"
chmod +x "$TL_TRIP/"*
export PATH="$TL_TRIP:$PATH"
export TRIPWIRE_LOG="${TRIPWIRE_LOG:-$TL_TRIP/tripwire.log}"
export TMPDIR="$TL_TMP/tmp"
export EVALS_OPERATOR_HOME="$TL_TMP/operator"
export EVALS_CREDENTIAL_SEED="$TL_TMP/seed"
export EVALS_WORKSPACE="$TL_TMP/ws"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset EVALS_REPO_ROOT EVALS_HARNESS_DIR EVALS_COST_PER_SESSION EVALS_OPERATOR_DBUS CLAUDE_CONFIG_DIR CODEX_HOME

tl_pass=0
tl_fail=0
ok() { tl_pass=$((tl_pass + 1)); printf 'ok - %s\n' "$1"; }
not_ok() { tl_fail=$((tl_fail + 1)); printf 'not ok - %s\n' "$1" >&2; }

# q COMMAND...: runs a command with its output discarded.
q() { "$@" >/dev/null 2>&1; }
# check DESC COMMAND...: passes when the command exits 0.
check() { local d="$1"; shift; if "$@"; then ok "$d"; else not_ok "$d"; fi; }
# refute DESC COMMAND...: passes when the command exits nonzero.
refute() { local d="$1"; shift; if "$@"; then not_ok "$d"; else ok "$d"; fi; }
# eq DESC EXPECTED ACTUAL
eq() { if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1 (expected [$2], got [$3])"; fi; }
# jeq DESC FILE JQ-FILTER EXPECTED: compares jq -c output.
jeq() { eq "$1" "$4" "$(jq -c "($3) | walk(if type == \"number\" then . + 0 else . end)" "$2" 2>&1)"; }
# contains DESC FILE FIXED-STRING
contains() { if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else not_ok "$1 ($2 lacks [$3])"; fi; }
lacks() { if grep -qF -- "$3" "$2" 2>/dev/null; then not_ok "$1 ($2 has [$3])"; else ok "$1"; fi; }

tl_git() { git -c user.name=tests -c user.email=tests@example.invalid -c commit.gpgsign=false "$@"; }

# A throwaway repository holding the fixture skill, its cases, and a README
# scoreboard, committed once. Prints its path.
tl_make_repo() { # $1 name
  local d="$TL_TMP/$1"
  mkdir -p "$d"
  cp -R "$TL_FIX/repo/." "$d/"
  ( cd "$d" && git init -q --template= && tl_git add -A && tl_git commit -q --no-verify -m fixture ) >/dev/null 2>&1 \
    || { not_ok "could not build the fixture repository"; return 1; }
  printf '%s\n' "$d"
}

# Points the runners at a fixture repo, the fake adapter, and the scripted agent.
tl_use_fake() { # $1 repo
  export EVALS_REPO_ROOT="$1"
  export EVALS_HARNESS_DIR="$TL_TESTS/fake-cli"
  export FAKE_AGENT="$TL_FIX/agent.sh"
  export FAKE_STATE="$TL_TMP/state"
  export FAKE_LAUNCH_LOG="$TL_TMP/state/launch.log"
  rm -rf "$FAKE_STATE"
  mkdir -p "$FAKE_STATE"
  : > "$FAKE_LAUNCH_LOG"
}

tl_launches() { if [ -f "$FAKE_LAUNCH_LOG" ]; then wc -l < "$FAKE_LAUNCH_LOG" | tr -d ' '; else echo 0; fi; }

tl_done() {
  local log
  for log in "$TL_TRIP/tripwire.log" "$TRIPWIRE_LOG"; do
    if [ -s "$log" ]; then
      not_ok "the tripwire fired: a suite reached a real agent CLI"
      cat "$log" >&2
      : > "$log"
    fi
  done
  printf '# %s: %d passed, %d failed\n' "$TL_NAME" "$tl_pass" "$tl_fail"
  [ "$tl_fail" -eq 0 ]
  exit $?
}
