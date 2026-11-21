#!/usr/bin/env bash
# `npx skills add` driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# Installs SKILL.md files only (no hooks) from the plugin directory into an
# isolated HOME, as a global Claude Code target. The CLI version is pinned and
# its telemetry disabled; the operator's npm cache is reused.

skills_cli_pkg="skills@1.5.26"
skills_cli_cache="${npm_config_cache:-${HOME:-}/.npm}"

adapter_check() {
  command -v npx >/dev/null 2>&1 || { echo "no \`npx\` on PATH" >&2; return 3; }
}

adapter_version() { echo "$skills_cli_pkg"; }

skills_cli() {
  env HOME="$harness_home" npm_config_cache="$skills_cli_cache" DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 \
    npx --yes "$skills_cli_pkg" "$@" </dev/null
}

adapter_install() { # $1 repo root, $2 plugin name
  harness_home="$(mktemp -d)"
  plugin_root="$harness_home/.claude/skills"
  (cd "$harness_home" && skills_cli add "$1/plugins/$2" --skill '*' -a claude-code -g -y --copy) >>"$errlog" 2>&1 || {
    echo "npx $skills_cli_pkg add failed" >>"$errlog"; return 1; }
}

adapter_inventory() { # $1 plugin name
  find "$plugin_root" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | sed 's|/SKILL.md$||; s|.*/||'
}
