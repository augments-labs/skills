#!/usr/bin/env bash
# Codex CLI driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# Installs through the repository's .agents/plugins/marketplace.json into an
# isolated CODEX_HOME, the same path a user's `codex plugin add` takes. No
# credentials are needed to install.

adapter_check() {
  command -v codex >/dev/null 2>&1 || { echo "no \`codex\` CLI on PATH" >&2; return 3; }
}

adapter_version() { codex --version 2>/dev/null | head -n 1; }

adapter_install() { # $1 repo root, $2 plugin name
  local out marketplace
  harness_home="$(mktemp -d)"
  marketplace="$(jq -r '.name' "$1/.agents/plugins/marketplace.json")"
  env CODEX_HOME="$harness_home" codex plugin marketplace add "$1" --json >/dev/null 2>>"$errlog" || {
    echo "codex plugin marketplace add failed" >>"$errlog"; return 1; }
  out="$(env CODEX_HOME="$harness_home" codex plugin add "$2@$marketplace" --json 2>>"$errlog")" || {
    echo "codex plugin add failed" >>"$errlog"; return 1; }
  plugin_root="$(printf '%s' "$out" | jq -r '.installedPath // empty')"
  [ -n "$plugin_root" ] && [ -f "$plugin_root/.codex-plugin/plugin.json" ] || {
    echo "codex reported no installed copy with .codex-plugin/plugin.json" >>"$errlog"; return 1; }
}

# Codex resolves skills from the installed copy's manifest `skills` path.
adapter_inventory() { # $1 plugin name
  local rel
  rel="$(jq -r '.skills // empty' "$plugin_root/.codex-plugin/plugin.json")"
  [ -n "$rel" ] || return 0
  find "$plugin_root/$rel" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null |
    sed 's|/SKILL.md$||; s|.*/||'
}
