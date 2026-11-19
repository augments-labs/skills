#!/usr/bin/env bash
# Claude Code driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# Claude Code loads a plugin tree in place with --plugin-dir; an isolated
# CLAUDE_CONFIG_DIR keeps any copy installed for the operator from answering
# for the tree under test. `plugin details` needs no credentials.

adapter_check() {
  command -v claude >/dev/null 2>&1 || { echo "no \`claude\` CLI on PATH" >&2; return 3; }
}

adapter_version() { claude --version 2>/dev/null | head -n 1; }

adapter_install() { # $1 repo root, $2 plugin name
  harness_home="$(mktemp -d)"
  plugin_root="$1/plugins/$2"
}

# The skills Claude Code itself resolved from the plugin, one name per line.
adapter_inventory() { # $1 plugin name
  env CLAUDE_CONFIG_DIR="$harness_home" claude --plugin-dir "$plugin_root" plugin details "$1" 2>>"$errlog" |
    awk '/^  Skills \([0-9]+\)/ {
      sub(/^  Skills \([0-9]+\)[[:space:]]*/, "")
      gsub(/,[[:space:]]*/, "\n")
      print
    }'
}
