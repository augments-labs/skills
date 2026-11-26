#!/usr/bin/env bash
# Cursor CLI (`cursor-agent`) driver. Sourced by tests/run-plugin-smoke.sh,
# never executed.
#
# Cursor loads local plugins from ~/.cursor/plugins/local/<name>/, so copying
# the bundle there (it carries .cursor-plugin/plugin.json) under an isolated
# HOME is the install. The inventory starts `cursor-agent acp`, opens a
# session, and reads the commands Cursor announces for it; no prompt is sent,
# so no model is called.
#
# Every cursor-agent command needs a signed-in account. This driver never
# copies credentials into the isolated HOME; it passes CURSOR_API_KEY through
# only when the operator exported it. Without it the inventory fails with
# Cursor's own sign-in error. The command naming below has not been observed
# on a signed-in run: names are accepted as `<plugin>:<skill>` or as a skill
# directory of the installed copy.

adapter_check() {
  command -v cursor-agent >/dev/null 2>&1 || { echo "no \`cursor-agent\` CLI on PATH" >&2; return 3; }
}

# In a throwaway home like every other call. Any cursor-agent run, this one
# included, briefly adds a pid file under its own install folder's .running/.
adapter_version() {
  local h; h="$(mktemp -d)"
  (cd "$h" && exec env -i PATH="$PATH" HOME="$h" TERM=dumb cursor-agent --version </dev/null) 2>/dev/null | head -n 1
  rm -rf "$h"
}

adapter_install() { # $1 repo root, $2 plugin name
  harness_home="$(mktemp -d)"
  plugin_root="$harness_home/.cursor/plugins/local/$2"
  mkdir -p "$harness_home/work" "$plugin_root"
  # Copied, not linked: Cursor rejects a link that points outside that folder.
  cp -R "$1/plugins/$2/." "$plugin_root/" 2>>"$errlog" || {
    echo "could not copy plugins/$2 to $plugin_root" >>"$errlog"; return 1; }
}

adapter_inventory() { # $1 plugin name
  local out="$harness_home/acp.out" stop="$harness_home/acp.stop" init auth new pid n=0
  init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":false,"writeTextFile":false},"terminal":false}}}'
  auth='{"jsonrpc":"2.0","id":2,"method":"authenticate","params":{"methodId":"cursor_login"}}'
  new="$(jq -cn --arg cwd "$harness_home/work" \
    '{jsonrpc: "2.0", id: 3, method: "session/new", params: {cwd: $cwd, mcpServers: []}}')"
  : >"$out"
  # `acp` does not exit at end of input: stdin stays open until $stop exists
  # (or 30 s pass), and the server is stopped by pid.
  { printf '%s\n%s\n%s\n' "$init" "$auth" "$new"
    i=0; while [ ! -f "$stop" ] && [ "$i" -lt 150 ]; do sleep 0.2; i=$((i + 1)); done
  } | (cd "$harness_home/work" &&
    exec env -i PATH="$PATH" HOME="$harness_home" TERM=dumb ${CURSOR_API_KEY:+CURSOR_API_KEY="$CURSOR_API_KEY"} \
      cursor-agent acp) >"$out" 2>>"$errlog" &
  pid=$!
  while [ "$n" -lt 150 ] && kill -0 "$pid" 2>/dev/null &&
    ! grep -q -e available_commands_update -e '"error"' "$out"; do
    sleep 0.2; n=$((n + 1))
  done
  # Later updates may add commands; give them a moment.
  grep -q available_commands_update "$out" && sleep 1
  : >"$stop"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  grep -q available_commands_update "$out" || {
    grep -v '^[[:space:]]*$' "$out" >>"$errlog"; echo "cursor-agent announced no commands" >>"$errlog"; return 1; }
  # Prefixed names are printed whatever they are, so an extra one shows.
  jq -r --arg p "$1:" '
    select(.method == "session/update" and .params.update.sessionUpdate == "available_commands_update") |
    .params.update.availableCommands[]? | .name | ltrimstr("/") |
    if startswith($p) then "plugin \(ltrimstr($p))" else "other \(.)" end' "$out" 2>>"$errlog" |
    while read -r kind name; do
      if [ "$kind" = plugin ] || [ -f "$plugin_root/skills/$name/SKILL.md" ]; then printf '%s\n' "$name"; fi
    done
}
