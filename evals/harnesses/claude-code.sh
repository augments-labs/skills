#!/usr/bin/env bash
# Claude Code adapter. Sourced by evals/bin/* after lib/common.sh,
# lib/home-env.sh, and lib/stream-text.sh, with HOME already pointing at the
# run's isolated home. See evals/README.md for the adapter contract.

adapter_name=claude-code
runnable=yes
runnable_reason=""

_cc_bundle=""

adapter_check() { command -v claude >/dev/null 2>&1; }

adapter_version() { claude --version 2>/dev/null | head -n 1; }

# Prepares the isolated config dir: the credential file only (never the
# operator's settings.json, which can carry hooks), a settings file that
# turns every hook off, and a private copy of the skill-only bundle.
adapter_install() { # $1 bundle dir, or "" for the none arm
  lab_home_is_isolated || return 1
  local cfg="$HOME/.claude" src="${CLAUDE_CONFIG_DIR:-${EVALS_OPERATOR_HOME:-}/.claude}"
  mkdir -p "$cfg" || return 1
  if [ -f "$src/.credentials.json" ] && [ ! -f "$cfg/.credentials.json" ]; then
    cp "$src/.credentials.json" "$cfg/.credentials.json" && chmod 0600 "$cfg/.credentials.json"
  fi
  printf '{"disableAllHooks": true}\n' > "$cfg/settings.json" || return 1
  _cc_bundle=""
  if [ -n "${1:-}" ]; then
    _cc_bundle="$HOME/.eval-plugin"
    rm -rf "$_cc_bundle" && cp -R "$1" "$_cc_bundle" || return 1
    mkdir -p "$_cc_bundle/.claude-plugin" || return 1
    printf '{"name": "eval-bundle", "version": "0.0.0"}\n' > "$_cc_bundle/.claude-plugin/plugin.json"
  fi
}

_cc_exec() { # $1 work dir, then claude arguments
  local wd="$1"; shift
  local extra=()
  [ -n "$_cc_bundle" ] && extra+=(--plugin-dir "$_cc_bundle")
  [ -n "${model:-}" ] && extra+=(--model "$model")
  ( cd "$wd" && lab_exec CLAUDE_CONFIG_DIR="$HOME/.claude" DISABLE_AUTOUPDATER=1 -- \
      claude "$@" --output-format stream-json --verbose ${extra[@]+"${extra[@]}"} )
}

adapter_run_behavioral() { # $1 work dir $2 prompt file $3 stream
  _cc_exec "$1" -p "$(cat "$2")" --permission-mode acceptEdits \
    --allowedTools Skill Read Glob Grep Write Edit Bash TodoWrite > "$3" 2>> "${errlog:-/dev/null}"
}

adapter_run_activation() { # $1 work dir $2 prompt $3 stream
  _cc_exec "$1" -p "$2" --max-turns "${maxturns:-6}" --tools "Skill,Read,Glob,Grep" \
    --allowedTools Skill Read Glob Grep > "$3" 2>> "${errlog:-/dev/null}"
}

# The skills the session loaded, one per line (plugin namespace stripped).
adapter_chain() {
  lab_json_events "$1" | jq -r 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and .name == "Skill") | .input.skill // empty | strings
    | sub("^.*:"; "")'
}

adapter_ran() { [ "$(lab_json_events "$1" | jq -s 'any(.[]; .type == "assistant")')" = true ]; }

adapter_output_tokens() {
  lab_json_events "$1" | jq -s -r '[.[] | select(.type == "result") | .usage.output_tokens // empty | numbers] | last // empty'
}

adapter_tool_calls() {
  lab_json_events "$1" | jq -s '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")] | length'
}

adapter_turns() {
  lab_json_events "$1" | jq -s -r '([.[] | select(.type == "result") | .num_turns // empty | numbers] | last)
    // ([.[] | select(.type == "assistant")] | length)'
}

adapter_session_model() {
  lab_json_events "$1" | jq -r 'select(.type == "system" and .subtype == "init") | .model // empty' | head -n 1
}
