#!/usr/bin/env bash
# Shared helpers for evals/bin/*. Sourced, never executed.

log() { printf '%s\n' "$*" >&2; }

die() { log "error: $*"; exit 1; }

require_tool() { # $* tool names; returns 127 naming the first missing one
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || { log "needs \`$t\`"; return 127; }
  done
}

# The evals/ directory (this file's grandparent) and the repository above it.
# EVALS_REPO_ROOT overrides the repository so the offline tests can point the
# tools at a throwaway repository.
evals_dir() { ( cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P ); }
repo_root() {
  if [ -n "${EVALS_REPO_ROOT:-}" ]; then ( cd "$EVALS_REPO_ROOT" && pwd -P ); return; fi
  ( cd "$(evals_dir)/.." && pwd -P )
}

evalkit() { python3 -I "$(evals_dir)/lib/evalkit.py" "$@"; }

# Where a harness adapter lives. EVALS_HARNESS_DIR overrides the directory so
# the offline tests can load the fake adapter.
adapter_path() { # $1 harness name
  case "$1" in ''|*/*|.*) return 2 ;; esac
  printf '%s/%s.sh\n' "${EVALS_HARNESS_DIR:-$(evals_dir)/harnesses}" "$1"
}

# The skill under test: skills/<pack>/<name>/ when promoted, otherwise
# skills/in-progress/<name>/. Prints the path relative to the repo root.
skill_rel_dir() { # $1 repo $2 pack $3 skill [$4 commit: resolve at that commit]
  local repo="$1" pack="$2" skill="$3" rev="${4:-}" d
  for d in "skills/$pack/$skill" "skills/in-progress/$skill"; do
    if [ -n "$rev" ]; then
      git -C "$repo" cat-file -e "$rev:$d/SKILL.md" 2>/dev/null && { printf '%s\n' "$d"; return 0; }
    else
      [ -f "$repo/$d/SKILL.md" ] && { printf '%s\n' "$d"; return 0; }
    fi
  done
  return 1
}

# The tree id of a directory at a commit: what an eval record binds to. Prints
# "null" when the working copy of that directory differs from the commit, so
# a record never claims a tree it did not measure.
skill_tree() { # $1 repo $2 commit $3 path [$4 "committed": skip the clean check]
  local t
  t="$(git -C "$1" rev-parse --verify --quiet "$2:$3" 2>/dev/null)" || { echo null; return; }
  if [ "${4:-}" != committed ] && [ -n "$(git -C "$1" status --porcelain --untracked-files=all -- "$3" 2>/dev/null)" ]; then
    log "warning: $3 has uncommitted changes; its skill_tree is recorded as null"
    echo null; return
  fi
  printf '%s\n' "$t"
}

# A skill-only bundle: <out>/skills/<name>/ holding SKILL.md and the scripts/,
# references/, and assets/ directories, nothing else. No hooks/, no settings,
# no manifest that could carry hooks, so every arm runs with hooks OFF.
build_bundle() { # $1 source skill dir $2 skill name $3 out dir
  local src="$1" name="$2" out="$3" sub
  [ -f "$src/SKILL.md" ] || { log "no SKILL.md in $src"; return 1; }
  mkdir -p "$out/skills/$name" || return 1
  cp "$src/SKILL.md" "$out/skills/$name/SKILL.md" || return 1
  for sub in scripts references assets; do
    [ -d "$src/$sub" ] && { cp -R "$src/$sub" "$out/skills/$name/$sub" || return 1; }
  done
  return 0
}

# A git work tree seeded from a fixture: the fixture's files committed as the
# "seed" commit, so changes are measured against it.
seed_workdir() { # $1 work dir $2 fixture dir ("" for a README-only tree)
  local wd="$1" fx="$2"
  mkdir -p "$wd" || return 1
  if [ -n "$fx" ]; then
    [ -d "$fx" ] || { log "no fixture directory: $fx"; return 1; }
    cp -R "$fx/." "$wd/" || return 1
  else
    printf '# Scratch project\n' > "$wd/README.md"
  fi
  ( cd "$wd" && git init -q --template= && git add -A \
      && git -c user.name=evals -c user.email=evals@example.invalid -c commit.gpgsign=false \
           commit -q --no-verify -m seed && git tag seed ) >/dev/null 2>&1
}

# The paths changed in a work tree since its seed commit, one per line, sorted:
# added (tracked or not), modified, deleted, and renamed (by destination).
lab_changed_files() { # $1 work tree $2 base commit
  ( set -o pipefail
    cd "$1" && { git diff --name-only -z -M "$2" -- && git ls-files -o --exclude-standard -z; } \
      | tr '\0' '\n' | LC_ALL=C sort -u )
}

# True when the provider refused the session (quota, login, credentials)
# rather than the model answering it.
lab_refusal() { # $1 stream $2 stderr log
  grep -qiE 'usage limit|login_required|api_error: 4|authentication required|authentication failed|quota exceeded|rate limit|resource_exhausted' "$1" 2>/dev/null \
    || grep -qiE 'usage limit|login_required|authorization grant|no credential|credential configured|not authenticated|invalid_grant|unauthorized|authentication required|authentication failed|quota exceeded|rate limit|resource_exhausted' "$2" 2>/dev/null
}

# Why a finished run cannot be scored, or nothing when it can. Indeterminate
# runs are counted apart and never averaged into a pass rate.
indeterminate_reason() { # $1 exit status $2 stream $3 stderr log $4 ran(0/1) $5 chain $6 arm
  local rc="$1" stream="$2" err="$3" ran="$4" chain="$5" arm="$6"
  lab_refusal "$stream" "$err" && { echo refusal; return; }
  [ "$rc" -eq 124 ] && { echo timeout; return; }
  [ "$rc" -ne 0 ] && { echo nonzero_exit; return; }
  [ "$ran" -eq 1 ] || { echo no_model_turn; return; }
  [ "$arm" = none ] && [ -n "$chain" ] && { echo skill_loaded_in_none; return; }
  return 0
}

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Stops a process and all of its descendants.
stop_tree() { # $1 pid
  local kid
  if command -v pgrep >/dev/null 2>&1; then
    for kid in $(pgrep -P "$1" 2>/dev/null); do stop_tree "$kid"; done
  fi
  kill "$1" 2>/dev/null || true
}

# Loads a harness adapter into this shell and checks it defines the contract.
load_adapter() { # $1 harness name
  local f fn
  f="$(adapter_path "$1")" && [ -f "$f" ] || { log "unknown harness: $1"; return 2; }
  # shellcheck disable=SC1090
  . "$f"
  for fn in adapter_check adapter_version adapter_install adapter_run_behavioral \
            adapter_run_activation adapter_supports_followups adapter_chain adapter_ran \
            adapter_output_tokens adapter_tool_calls adapter_turns adapter_session_model; do
    declare -F "$fn" >/dev/null || { log "adapter $1 does not define $fn"; return 2; }
  done
  [ "${runnable:-}" = yes ] || [ "${runnable:-}" = no ] || { log "adapter $1 sets no runnable=yes|no"; return 2; }
}

# Refuses an adapter marked runnable=no unless the operator allows it.
adapter_gate() { # $1 harness $2 allow-unverified (0/1)
  adapter_check || { log "the $1 CLI is not on PATH"; return 3; }
  if [ "$runnable" != yes ] && [ "$2" -ne 1 ]; then
    log "$1 is marked runnable=no (${runnable_reason:-no reason}); pass --allow-unverified to run it anyway"
    return 2
  fi
}

# Sends a session's follow-up messages in order, calling COMMAND... MESSAGE
# once per message in the follow-ups file (a JSON array of strings). The
# whole session shares one $timeout_s: each call gets what is left of it
# since START (a $SECONDS reading taken before the first prompt), and a
# session with nothing left ends as a timeout (124). Stops at the first
# nonzero status and returns it.
lab_each_followup() { # $1 follow-ups file $2 start, then COMMAND...
  local file="$1" start="$2" n i msg left
  shift 2
  n="$(jq -e 'arrays | length' "$file" 2>/dev/null)" || return 1
  for ((i = 0; i < n; i++)); do
    msg="$(jq -e -r --argjson i "$i" '.[$i] | strings' "$file" 2>/dev/null)" || return 1
    if [ -n "${timeout_s:-}" ] && [ "$timeout_s" -gt 0 ] 2>/dev/null; then
      left=$((timeout_s - (SECONDS - start)))
      [ "$left" -gt 0 ] || return 124
      timeout_s="$left" "$@" "$msg" || return $?
    else
      "$@" "$msg" || return $?
    fi
  done
}

# Runs one agent session in a throwaway home: seeds credentials, installs the
# bundle ("" for none), then calls the adapter. A follow-ups file goes to the
# adapter as a fourth argument; an adapter that cannot send follow-ups gets
# no session at all (setup_failed=followups_unsupported), so a multi-turn
# case is never graded on its first turn alone. Sets setup_failed when the
# home could not be prepared. Returns the session's exit status. Stdin is
# detached so a session never drains a caller's read loop.
lab_session() { # $1 base dir $2 bundle $3 kind (behavioral|activation) $4 work dir $5 prompt (file for behavioral) $6 stream $7 stderr log [$8 follow-ups file]
  local base="$1" bundle="$2" kind="$3" wd="$4" prompt="$5" stream="$6" err="$7" followups="${8:-}" rc=0
  setup_failed=""
  if [ -n "$followups" ] && ! adapter_supports_followups; then
    setup_failed=followups_unsupported
    return 90
  fi
  (
    set +e
    eval "$(lab_home_env "$base")" || exit 90
    export LAB_RUN_BASE EVALS_OPERATOR_HOME EVALS_OPERATOR_DBUS HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR TMPDIR
    errlog="$err"
    lab_seed_credentials "$harness" || { echo credential_seed_failed > "$base/setup-failed"; exit 90; }
    adapter_install "$bundle" >> "$err" 2>&1 || { echo install_failed > "$base/setup-failed"; exit 90; }
    "adapter_run_$kind" "$wd" "$prompt" "$stream" ${followups:+"$followups"}
  ) < /dev/null || rc=$?
  lab_home_cleanup "$base"
  if [ -f "$base/setup-failed" ]; then
    setup_failed="$(cat "$base/setup-failed")"; rm -f "$base/setup-failed"
  elif [ "$rc" -eq 90 ]; then
    setup_failed=home_setup_failed
  fi
  return "$rc"
}
