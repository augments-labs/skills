#!/usr/bin/env bash
# Devin CLI driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# Installs the bundle (it carries .devin-plugin/plugin.json) with
# `devin plugins install --local --yes`, under an isolated HOME, and lists the
# skills Devin resolves from it with `devin skills list --json`.
#
# Devin refuses to manage plugins while signed out, even a local folder. Its
# sign-in lives in stored credentials (no environment variable), and this
# driver never copies credentials into the isolated HOME, so the install stops
# at Devin's own sign-in error: the run fails rather than passing unverified.

adapter_check() {
  command -v devin >/dev/null 2>&1 || { echo "no \`devin\` CLI on PATH" >&2; return 3; }
}

# In a throwaway home like every other call (harness_home is shadowed here).
adapter_version() {
  local harness_home; harness_home="$(mktemp -d)"; mkdir -p "$harness_home/work"
  devin_env devin --version 2>/dev/null | head -n 1
  rm -rf "$harness_home"
}

devin_env() {
  (cd "$harness_home/work" && env -i PATH="$PATH" HOME="$harness_home" TERM=dumb "$@" </dev/null)
}

adapter_install() { # $1 repo root, $2 plugin name
  harness_home="$(mktemp -d)"
  mkdir -p "$harness_home/work"
  plugin_root="$(cd "$1/plugins/$2" && pwd -P)" || return 1
  devin_env devin plugins install --local --yes "$plugin_root" >>"$errlog" 2>&1 || {
    echo "devin plugins install failed" >>"$errlog"; return 1; }
}

# The skills Devin resolves, kept to the ones it found under this bundle.
adapter_inventory() { # $1 plugin name
  devin_env devin skills list --json 2>>"$errlog" |
    jq -r --arg dir "/plugins/$1/skills/" '.[] | select((.base_dir // "") | contains($dir)) | .name' 2>>"$errlog"
}
