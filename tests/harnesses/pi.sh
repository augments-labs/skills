#!/usr/bin/env bash
# pi driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# `pi install <path>` records the package in ~/.pi/agent/settings.json, so it
# runs under an isolated HOME. The repository root installs through the `pi`
# key of package.json; a pack that key does not list installs from its bundle,
# where pi finds skills/ by convention. No credentials are needed.

adapter_check() {
  command -v pi >/dev/null 2>&1 || { echo "no \`pi\` CLI on PATH" >&2; return 3; }
}

# Run in a throwaway HOME: even `pi --version` writes under ~/.pi.
adapter_version() {
  local h; h="$(mktemp -d)"
  (cd "$h" && exec env -i PATH="$PATH" HOME="$h" TERM=dumb PI_OFFLINE=1 pi --version </dev/null) 2>/dev/null | head -n 1
  rm -rf "$h"
}

pi_env() { env -i PATH="$PATH" HOME="$harness_home" TERM=dumb PI_OFFLINE=1 "$@"; }

adapter_install() { # $1 repo root, $2 plugin name
  local source="$1/plugins/$2"
  harness_home="$(mktemp -d)"
  plugin_root="$(cd "$1/plugins/$2" && pwd -P)" || return 1
  if jq -e --arg p "./plugins/$2/skills" '.pi.skills // [] | index($p)' "$1/package.json" >/dev/null 2>&1; then
    source="$1"
  fi
  mkdir -p "$harness_home/work"
  (cd "$harness_home/work" && pi_env pi install "$source" </dev/null) >>"$errlog" 2>&1 || {
    echo "pi install $source failed" >>"$errlog"; return 1; }
}

# The skill commands pi itself loaded, kept to the ones under this bundle.
adapter_inventory() { # $1 plugin name
  local out
  out="$(cd "$harness_home/work" && printf '{"id":"1","type":"get_commands"}\n' |
    pi_env pi --mode rpc --no-session --no-extensions 2>>"$errlog")" || {
    echo "pi --mode rpc failed" >>"$errlog"; return 1; }
  printf '%s\n' "$out" | jq -r --arg dir "$plugin_root/skills/" '
    select(.type == "response" and .command == "get_commands") |
    if .success then .data.commands[] else error("get_commands failed") end |
    select(.source == "skill" and (.sourceInfo.path // "" | startswith($dir))) |
    .name | sub("^skill:"; "")' 2>>"$errlog"
}
