#!/usr/bin/env bash
# Kimi Code driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# Kimi installs plugins from its `/plugins install <path-or-zip-url>` command,
# which its local web server also exposes. The driver starts `kimi web` under
# an isolated HOME and KIMI_CODE_HOME, installs through that API, and lists
# the skills a new session loads. The root pack installs from the repository
# root (.kimi-plugin/plugin.json there), any other pack from its bundle.
# Signed out and with no model configured: nothing here calls a model.

adapter_check() {
  command -v kimi >/dev/null 2>&1 || { echo "no \`kimi\` CLI on PATH" >&2; return 3; }
  command -v curl >/dev/null 2>&1 || { echo "no \`curl\` on PATH" >&2; return 3; }
}

# In a throwaway home like every other call.
adapter_version() {
  local h; h="$(mktemp -d)"
  (cd "$h" && exec env -i PATH="$PATH" HOME="$h" KIMI_CODE_HOME="$h/.kimi-code" TERM=dumb kimi --version </dev/null) \
    2>/dev/null | head -n 1
  rm -rf "$h"
}

kimi_pid="" kimi_origin="" kimi_token=""

kimi_api() { # METHOD PATH [JSON]
  curl -sS -X "$1" -H "Authorization: Bearer $kimi_token" -H 'Content-Type: application/json' \
    ${3:+--data "$3"} "$kimi_origin$2"
}

# Stops the server after 300 s if an interrupted run left it behind.
kimi_watchdog() { # $1 pid
  (n=0
    while [ "$n" -lt 300 ] && kill -0 "$1" 2>/dev/null; do sleep 1; n=$((n + 1)); done
    kill "$1" 2>/dev/null) >/dev/null 2>&1 &
}

# Waits up to $2 tenths of a second for pid $1 to exit.
kimi_wait_exit() {
  local n=0
  while [ "$n" -lt "$2" ] && kill -0 "$1" 2>/dev/null; do sleep 0.1; n=$((n + 1)); done
  ! kill -0 "$1" 2>/dev/null
}

# Kimi keeps writing its home while it shuts down, so wait for it to exit:
# otherwise it recreates the isolated home after the runner removes it.
kimi_stop() {
  [ -n "$kimi_pid" ] || return 0
  kimi_api POST /api/v1/shutdown "{}" >/dev/null 2>&1
  kimi_wait_exit "$kimi_pid" 150 || { kill "$kimi_pid" 2>/dev/null; kimi_wait_exit "$kimi_pid" 50; } ||
    kill -9 "$kimi_pid" 2>/dev/null
  kimi_pid=""
}

adapter_install() { # $1 repo root, $2 plugin name
  local source="$1/plugins/$2" out i
  harness_home="$(mktemp -d)"
  mkdir -p "$harness_home/work"
  if [ "$(jq -r '.name // empty' "$1/.kimi-plugin/plugin.json" 2>/dev/null)" = "$2" ]; then
    source="$1"
  fi
  (cd "$harness_home/work" &&
    exec env -i PATH="$PATH" HOME="$harness_home" KIMI_CODE_HOME="$harness_home/.kimi-code" TERM=dumb \
      kimi web --json --port 0 </dev/null >"$harness_home/web.json" 2>>"$errlog") &
  kimi_pid=$!
  kimi_watchdog "$kimi_pid"
  for i in $(seq 1 150); do
    grep -q '"token"' "$harness_home/web.json" 2>/dev/null && break
    kill -0 "$kimi_pid" 2>/dev/null || break
    sleep 0.2
  done
  kimi_origin="$(head -n 1 "$harness_home/web.json" 2>/dev/null | jq -r '.origin // empty' 2>/dev/null)"
  kimi_token="$(head -n 1 "$harness_home/web.json" 2>/dev/null | jq -r '.token // empty' 2>/dev/null)"
  [ -n "$kimi_origin" ] && [ -n "$kimi_token" ] || {
    echo "kimi web did not start" >>"$errlog"; kimi_stop; return 1; }
  out="$(kimi_api POST /api/v1/plugins "$(jq -cn --arg s "$source" '{source: $s}')" 2>>"$errlog")"
  printf '%s' "$out" | jq -e --arg p "$2" \
    '.code == 0 and .data.id == $p and .data.state == "ok" and (.data.has_errors | not)' >/dev/null 2>&1 || {
    printf '%s\n' "$out" >>"$errlog"; echo "kimi plugin install from $source failed" >>"$errlog"; kimi_stop; return 1; }
  [ "$(printf '%s' "$out" | jq -r '.data.hook_count')" = 0 ] || {
    printf '%s\n' "$out" >>"$errlog"; echo "kimi loaded hooks from $2" >>"$errlog"; kimi_stop; return 1; }
}

# The plugin skills a new session loads (named <plugin>:<skill>).
adapter_inventory() { # $1 plugin name
  local sid rc=0
  sid="$(kimi_api POST /api/v1/sessions "$(jq -cn --arg c "$harness_home/work" '{metadata: {cwd: $c}}')" \
    2>>"$errlog" | jq -r '.data.id // empty' 2>>"$errlog")"
  if [ -z "$sid" ]; then
    echo "kimi could not create a session" >>"$errlog"; rc=1
  else
    kimi_api GET "/api/v1/sessions/$sid/skills" 2>>"$errlog" |
      jq -r --arg p "$1:" '.data | (if type == "array" then . else .skills end) | .[] |
        .name | select(startswith($p)) | ltrimstr($p)' 2>>"$errlog" || rc=1
  fi
  kimi_stop
  return "$rc"
}
