#!/usr/bin/env bash
# Antigravity (`agy`) driver. Sourced by tests/run-plugin-smoke.sh, never
# executed. `agy plugin install` copies the plugin directory into
# ~/.gemini/config/plugins/<name>, so it runs under an isolated HOME; a local
# install needs no sign-in.

adapter_check() {
  command -v agy >/dev/null 2>&1 || { echo "no \`agy\` CLI on PATH" >&2; return 3; }
}

adapter_version() { agy --version 2>/dev/null | head -n 1; }

adapter_install() { # $1 repo root, $2 plugin name
  harness_home="$(mktemp -d)"
  (cd "$harness_home" && HOME="$harness_home" agy plugin install "$1/plugins/$2" </dev/null) >>"$errlog" 2>&1 || {
    echo "agy plugin install failed" >>"$errlog"; return 1; }
  plugin_root="$harness_home/.gemini/config/plugins/$2"
  [ -f "$plugin_root/.antigravity-plugin/plugin.json" ] || {
    echo "installed copy has no .antigravity-plugin/plugin.json" >>"$errlog"; return 1; }
}

# `agy plugin validate` reports how many skills the loader processes but not
# their names, so names are read from the installed copy and accepted only
# when both counts agree and the loader reports no errors.
adapter_inventory() { # $1 plugin name
  local report processed errors names
  report="$(HOME="$harness_home" agy plugin validate "$plugin_root" --json </dev/null 2>>"$errlog")" || {
    echo "agy plugin validate failed: $report" >>"$errlog"; return 1; }
  processed="$(printf '%s' "$report" | jq -r '.components.skills // 0')"
  errors="$(printf '%s' "$report" | jq -r '[.findings[]? | select(.severity == "error")] | length')"
  names="$(find "$plugin_root/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | sed 's|/SKILL.md$||; s|.*/||')"
  if [ "$errors" -ne 0 ]; then
    printf '%s' "$report" | jq -r '.findings[] | select(.severity == "error") | "agy: \(.file): \(.message)"' >>"$errlog"
    return 1
  fi
  if [ "$processed" -ne "$(printf '%s\n' "$names" | grep -c .)" ]; then
    echo "agy processed $processed skills; the installed copy holds $(printf '%s\n' "$names" | grep -c .)" >>"$errlog"
    return 1
  fi
  printf '%s\n' "$names"
}
