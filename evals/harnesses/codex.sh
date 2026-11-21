#!/usr/bin/env bash
# Codex CLI adapter. Sourced by evals/bin/* after lib/common.sh,
# lib/home-env.sh, and lib/stream-text.sh, with HOME already pointing at the
# run's isolated home. See evals/README.md for the adapter contract.

adapter_name=codex
runnable=no
runnable_reason="launch flags and user-skill discovery are not yet verified against a live CLI"

adapter_check() { command -v codex >/dev/null 2>&1; }

adapter_version() { codex --version 2>/dev/null | head -n 1; }

# CODEX_HOME holds only auth.json (never config.toml, which can carry hooks,
# notify commands, or MCP servers) plus the bundle's skills under skills/.
adapter_install() { # $1 bundle dir, or "" for the none arm
  lab_home_is_isolated || return 1
  local home="$HOME/.codex" src="${CODEX_HOME:-${EVALS_OPERATOR_HOME:-}/.codex}"
  mkdir -p "$home" || return 1
  if [ -f "$src/auth.json" ] && [ ! -f "$home/auth.json" ]; then
    cp "$src/auth.json" "$home/auth.json" && chmod 0600 "$home/auth.json"
  fi
  rm -rf "$home/skills"
  if [ -n "${1:-}" ]; then
    cp -R "$1/skills" "$home/skills" || return 1
  fi
}

_cx_exec() { # $1 work dir, then codex exec arguments
  local wd="$1"; shift
  local extra=()
  [ -n "${model:-}" ] && extra+=(-m "$model")
  ( cd "$wd" && lab_exec CODEX_HOME="$HOME/.codex" -- \
      codex exec --json --skip-git-repo-check -C "$wd" ${extra[@]+"${extra[@]}"} "$@" )
}

# Follow-ups resume the run's latest session (CODEX_HOME holds only this
# run's sessions) from the same work tree and append their events to the
# stream. Like the rest of this adapter, not yet verified against a live CLI.
adapter_run_behavioral() { # $1 work dir $2 prompt file $3 stream [$4 follow-ups file]
  local start="$SECONDS"
  _cx_exec "$1" --full-auto "$(cat "$2")" > "$3" 2>> "${errlog:-/dev/null}" || return $?
  [ -z "${4:-}" ] || lab_each_followup "$4" "$start" _cx_followup "$1" "$3"
}

_cx_followup() { # $1 work dir $2 stream $3 message
  _cx_exec "$1" --full-auto resume --last "$3" >> "$2" 2>> "${errlog:-/dev/null}"
}

adapter_supports_followups() { true; }

adapter_run_activation() { # $1 work dir $2 prompt $3 stream
  _cx_exec "$1" -s read-only "$2" > "$3" 2>> "${errlog:-/dev/null}"
}

# A skill counts as loaded when the session reads its SKILL.md.
adapter_chain() {
  lab_json_events "$1" | jq -r 'select(.type == "item.completed") | .item
    | select(.type == "command_execution") | .command // empty | strings
    | capture("skills/(?<n>[A-Za-z0-9._-]+)/SKILL\\.md")? | .n' | awk '!seen[$0]++'
}

adapter_ran() {
  [ "$(lab_json_events "$1" | jq -s 'any(.[]; .type == "turn.completed"
    or (.type == "item.completed" and .item.type == "agent_message"))')" = true ]
}

adapter_output_tokens() {
  lab_json_events "$1" | jq -s -r '[.[] | select(.type == "turn.completed") | .usage.output_tokens // empty | numbers]
    | if length > 0 then add else empty end'
}

adapter_tool_calls() {
  lab_json_events "$1" | jq -s '[.[] | select(.type == "item.completed") | .item.type
    | select(. == "command_execution" or . == "file_change" or . == "mcp_tool_call" or . == "web_search")] | length'
}

adapter_turns() { lab_json_events "$1" | jq -s '[.[] | select(.type == "turn.completed")] | length'; }

adapter_session_model() { :; }
