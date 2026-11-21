#!/usr/bin/env bash
# Muse Code driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# Adds the repository as a marketplace (.claude-plugin/marketplace.json) and
# installs the plugin from it, under an isolated HOME and XDG_CONFIG_HOME. No
# credentials are needed. Muse must pick the bundle's own manifest, which
# lists no hooks, so the inventory also fails if Muse loads any hook from it.

adapter_check() {
  command -v muse >/dev/null 2>&1 || { echo "no \`muse\` CLI on PATH" >&2; return 3; }
}

# In a throwaway home like every other call (harness_home is shadowed here).
adapter_version() {
  local harness_home; harness_home="$(mktemp -d)"; mkdir -p "$harness_home/work"
  muse_env muse --version 2>/dev/null | head -n 1
  rm -rf "$harness_home"
}

muse_env() {
  (cd "$harness_home/work" &&
    env -i PATH="$PATH" HOME="$harness_home" XDG_CONFIG_HOME="$harness_home/.config" \
      MUSE_NO_AUTO_UPDATE=1 TERM=dumb "$@" </dev/null)
}

adapter_install() { # $1 repo root, $2 plugin name
  local marketplace out
  harness_home="$(mktemp -d)"
  mkdir -p "$harness_home/work"
  marketplace="$(jq -r '.name' "$1/.claude-plugin/marketplace.json")"
  muse_env muse plugins marketplace add "$marketplace" "$1" --json >>"$errlog" 2>&1 || {
    echo "muse plugins marketplace add failed" >>"$errlog"; return 1; }
  out="$(muse_env muse plugins install "$2@$marketplace" --json 2>>"$errlog")" || {
    printf '%s\n' "$out" >>"$errlog"; echo "muse plugins install failed" >>"$errlog"; return 1; }
  [ "$(printf '%s' "$out" | jq -r '.installed.manifest_family // empty')" = native ] || {
    printf '%s\n' "$out" >>"$errlog"; echo "muse did not select .muse-plugin/plugin.json" >>"$errlog"; return 1; }
}

# The skills Muse itself resolves from the installed plugin (ids are
# plugin:<plugin>:<skill>; Muse also ships plugins of its own).
adapter_inventory() { # $1 plugin name
  local hooks
  hooks="$(muse_env muse plugins list --json 2>>"$errlog" | jq -r --arg p "$1" \
    '[.plugins[]? | select(.plugin.id == $p) | .plugin.capabilities.hooks[]?] | length' 2>>"$errlog")"
  [ "$hooks" = 0 ] || { echo "muse loaded ${hooks:-unknown} hook(s) from $1" >>"$errlog"; return 1; }
  muse_env muse skills list --source plugin --json 2>>"$errlog" |
    jq -r --arg p "plugin:$1:" '.skills[]? | .id | select(startswith($p)) | ltrimstr($p)' 2>>"$errlog"
}
