#!/usr/bin/env bash
# Isolated harness homes. Sourced, never executed.
#
# Every agent session runs with a throwaway HOME under TMPDIR, outside any
# repository, so the CLI reads no operator configuration, no settings that
# carry hooks, and no instruction file from a parent directory. Only
# credential files are seeded into it, and the home is removed after the run.

# Prints VAR=value lines for a run's isolated home; eval them, then export.
lab_home_env() { # $1 base directory for this run (created when missing)
  [ "$#" -eq 1 ] || return 127
  local base="$1" home="$1/home"
  mkdir -p "$home/.config" "$home/.local/share" "$home/.cache" "$base/tmp" "$base/run" || return 127
  chmod 0700 "$home" "$base/run" || return 127
  printf 'LAB_RUN_BASE=%q\n' "$base"
  printf 'EVALS_OPERATOR_HOME=%q\n' "${EVALS_OPERATOR_HOME:-${HOME:-}}"
  printf 'HOME=%q\n' "$home"
  printf 'XDG_CONFIG_HOME=%q\n' "$home/.config"
  printf 'XDG_DATA_HOME=%q\n' "$home/.local/share"
  printf 'XDG_CACHE_HOME=%q\n' "$home/.cache"
  printf 'XDG_RUNTIME_DIR=%q\n' "$base/run"
  printf 'TMPDIR=%q\n' "$base/tmp"
}

# True only when HOME is the run's isolated home, so an adapter never writes
# into the operator's real configuration.
lab_home_is_isolated() {
  [ -n "${LAB_RUN_BASE:-}" ] && [ "${HOME:-}" = "$LAB_RUN_BASE/home" ] && return 0
  log "refusing: HOME is not an isolated run home"
  return 1
}

# Copies one harness's credential seed into the isolated home, mode 0600.
# The seed directory mirrors the home's layout; a .eval-env file in it
# (KEY=value lines) is sourced by the child process only, never by the runner.
lab_seed_credentials() { # $1 harness
  [ "$#" -eq 1 ] || return 127
  lab_home_is_isolated || return 127
  local seed="${EVALS_CREDENTIAL_SEED:-${EVALS_OPERATOR_HOME:-}/.config/augments-skills/eval-credentials}/$1"
  [ -d "$seed" ] || return 0
  cp -R "$seed/." "$HOME/" || return 127
  find "$HOME" -type f -exec chmod 0600 {} + || return 127
}

# Runs a command with a cleared environment: the isolated home, its XDG
# directories, a runtime directory with no session bus in it (so no route to
# the operator's secret store), PATH, and the extra VAR=value pairs given
# before "--". Honors $timeout_s (seconds) when set.
lab_exec() { # [VAR=value ...] -- command [args...]
  local extra=() t=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do extra+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  [ -n "${timeout_s:-}" ] && [ "${timeout_s}" -gt 0 ] 2>/dev/null && t=(timeout -k 10 "$timeout_s")
  env -i PATH="$PATH" HOME="$HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" TMPDIR="$TMPDIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/no-session-bus" \
    LANG=C.UTF-8 TERM=dumb NO_COLOR=1 ${extra[@]+"${extra[@]}"} \
    ${t[@]+"${t[@]}"} /bin/sh -c \
      'if [ -f "$HOME/.eval-env" ]; then set -a; . "$HOME/.eval-env"; set +a; fi; exec "$@"' eval-child "$@"
}

# Removes the isolated home (it holds credential copies) and its temp dirs.
lab_home_cleanup() { # $1 base directory
  [ "$#" -eq 1 ] && [ -n "$1" ] || return 127
  rm -rf "$1/home" "$1/tmp" "$1/run"
}
