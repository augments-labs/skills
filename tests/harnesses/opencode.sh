#!/usr/bin/env bash
# OpenCode driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# Everything runs under an isolated HOME and XDG directories, with no
# credentials and no model call (never `opencode run`).
#
# `opencode plugin add` takes a Git or npm specifier, the way a
# user installs the repository. For the root pack the driver commits a
# snapshot of the tree under test and adds git+file://<snapshot>, which loads
# the root index.js. Any other pack is listed by its bundle directory under
# `plugins` in opencode.json. The inventory is the skill list that
# `opencode serve` reports through `opencode api`.

# Run in a throwaway HOME: even `opencode --version` writes a log under it.
oc_version() {
  local h; h="$(mktemp -d)"
  (cd "$h" && exec env -i PATH="$PATH" HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_DATA_HOME="$h/.local/share" \
    XDG_CACHE_HOME="$h/.cache" XDG_STATE_HOME="$h/.local/state" TERM=dumb OPENCODE_DISABLE_AUTOUPDATE=1 \
    opencode --version </dev/null) 2>/dev/null | head -n 1
  rm -rf "$h"
}

adapter_check() {
  command -v opencode >/dev/null 2>&1 || { echo "no \`opencode\` CLI on PATH" >&2; return 3; }
  command -v git >/dev/null 2>&1 || { echo "no \`git\` on PATH" >&2; return 3; }
  opencode_version="$(oc_version)"
  opencode_major="$(printf '%s' "$opencode_version" | tr -cd '0-9.')"
  opencode_major="${opencode_major%%.*}"
  case "$opencode_major" in
    2) ;;
    *) echo "OpenCode 2.x required, found: $opencode_version" >&2; return 3 ;;
  esac
}

adapter_version() { printf '%s\n' "$opencode_version"; }

# Call inside ( ... ): it changes directory and execs.
oc_exec() {
  cd "$harness_home/work" &&
    exec env -i PATH="$PATH" HOME="$harness_home" XDG_CONFIG_HOME="$harness_home/.config" \
      XDG_DATA_HOME="$harness_home/.local/share" XDG_CACHE_HOME="$harness_home/.cache" \
      XDG_STATE_HOME="$harness_home/.local/state" TERM=dumb OPENCODE_DISABLE_AUTOUPDATE=1 \
      OPENCODE_DISABLE_MODELS_FETCH=1 OPENCODE_SERVER_PASSWORD=smoke "$@" </dev/null
}

adapter_install() { # $1 repo root, $2 plugin name
  local config root=0 snap
  harness_home="$(mktemp -d)"
  mkdir -p "$harness_home/work" "$harness_home/.config/opencode"
  config="$harness_home/.config/opencode/opencode.json"
  grep -q "\"./plugins/$2/index.js\"" "$1/index.js" 2>/dev/null && root=1

  if [ "$root" = 0 ]; then
    jq -n --arg p "$1/plugins/$2" '{plugins: [$p]}' >"$config"
    return 0
  fi
  snap="$harness_home/snapshot"
  mkdir -p "$snap"
  (cd "$1" && git ls-files -co --exclude-standard | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done | tar -cf - -T -) | tar -xf - -C "$snap" || { echo "could not copy $1" >>"$errlog"; return 1; }
  (cd "$snap" && env -i PATH="$PATH" HOME="$harness_home" GIT_CONFIG_NOSYSTEM=1 sh -c 'git init -q && git add -A &&
    git -c user.name=smoke -c user.email=smoke@localhost -c commit.gpgsign=false commit -qm snapshot') \
    >>"$errlog" 2>&1 || { echo "could not commit the snapshot" >>"$errlog"; return 1; }
  (oc_exec opencode plugin add "git+file://$snap") >>"$errlog" 2>&1 || {
    echo "opencode plugin add failed" >>"$errlog"; return 1; }
}

# Skills OpenCode resolved from this bundle. Any other skill outside OpenCode's
# built-ins (skill:// paths) is printed with its path so it counts as extra.
adapter_inventory() { # $1 plugin name
  local log="$harness_home/serve.log" url="" out="" pid i n rc=0
  local filter='.[] | (.path // .location // "") as $at |
    select($at | startswith("skill://") | not) |
    if ($at | contains($dir)) then .name else "\(.name) (\($at))" end'

  (oc_exec opencode serve --hostname 127.0.0.1 --port 0) >"$log" 2>&1 &
  pid=$!
  # Stops the server after 300 s if an interrupted run left it behind.
  (n=0
    while [ "$n" -lt 300 ] && kill -0 "$pid" 2>/dev/null; do sleep 1; n=$((n + 1)); done
    kill "$pid" 2>/dev/null) >/dev/null 2>&1 &
  for i in $(seq 1 150); do
    url="$(sed -n 's/.*listening on \(http[^ ]*\).*/\1/p' "$log" | head -n 1)"
    [ -n "$url" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  if [ -z "$url" ]; then
    echo "opencode serve did not start:" >>"$errlog"; cat "$log" >>"$errlog"; rc=1
  else
    # The list fills in while the server boots.
    for i in $(seq 1 40); do
      out="$( (oc_exec opencode api --server "$url" skill.list) 2>>"$errlog")"
      n="$(printf '%s' "$out" | jq '[.data[]? | select((.path // .location // "") | startswith("skill://") | not)] | length' 2>/dev/null)"
      [ "${n:-0}" -gt 0 ] && break
      sleep 0.25
    done
    printf '%s' "$out" | jq -r --arg dir "/plugins/$1/skills/" ".data // [] | $filter" 2>>"$errlog" || rc=1
    [ "${n:-0}" -gt 0 ] || printf 'opencode api skill.list returned: %s\n' "$out" >>"$errlog"
  fi
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return "$rc"
}
