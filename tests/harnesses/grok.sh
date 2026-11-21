#!/usr/bin/env bash
# Grok Build driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# Adds the repository as a marketplace (Grok reads .grok-plugin/marketplace.json)
# and installs the plugin from it, under an isolated HOME and GROK_HOME. No
# credentials are needed. The bundle's manifest lists no hooks, so the
# inventory also fails if Grok loads any hook from it.

adapter_check() {
  command -v grok >/dev/null 2>&1 || { echo "no \`grok\` CLI on PATH" >&2; return 3; }
}

# In a throwaway home like every other call (harness_home is shadowed here).
adapter_version() {
  local harness_home; harness_home="$(mktemp -d)"; mkdir -p "$harness_home/work"
  grok_env grok --version 2>/dev/null | head -n 1
  rm -rf "$harness_home"
}

grok_env() {
  (cd "$harness_home/work" &&
    env -i PATH="$PATH" HOME="$harness_home" GROK_HOME="$harness_home/grok" TERM=dumb "$@" </dev/null)
}

adapter_install() { # $1 repo root, $2 plugin name
  harness_home="$(mktemp -d)"
  mkdir -p "$harness_home/work"
  grok_env grok plugin marketplace add "$1" >>"$errlog" 2>&1 || {
    echo "grok plugin marketplace add failed" >>"$errlog"; return 1; }
  grok_env grok plugin install "$2" --trust >>"$errlog" 2>&1 || {
    echo "grok plugin install $2 failed" >>"$errlog"; return 1; }
}

# The skills Grok itself discovers from the installed plugin.
adapter_inventory() { # $1 plugin name
  local report hooks
  report="$(grok_env grok inspect --json 2>>"$errlog")" || {
    echo "grok inspect failed" >>"$errlog"; return 1; }
  hooks="$(printf '%s' "$report" | jq -r --arg p "$1" \
    '[.plugins[]? | select(.name == $p and .provides.hooks)] | length' 2>>"$errlog")"
  [ "$hooks" = 0 ] || { echo "grok loaded hooks from $1" >>"$errlog"; return 1; }
  printf '%s' "$report" | jq -r --arg p "$1" \
    '.skills[]? | select(.source.type == "plugin" and .source.plugin_name == $p) | .name' 2>>"$errlog"
}
