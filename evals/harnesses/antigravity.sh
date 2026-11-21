#!/usr/bin/env bash
# Antigravity CLI adapter. Sourced by evals/bin/* after lib/common.sh,
# lib/home-env.sh, and lib/stream-text.sh, with HOME already pointing at the
# run's isolated home. See evals/README.md for the adapter contract.

adapter_name=antigravity
runnable=yes
runnable_reason=""

_agy_use_keyring=0

adapter_check() { command -v agy >/dev/null 2>&1; }

adapter_version() { agy --version 2>/dev/null | head -n 1; }

# Auth mirrors claude-code: a credential seed under
# $EVALS_CREDENTIAL_SEED/antigravity/ (such as .eval-env with an API key or
# seeded OAuth files) takes precedence with the session bus blocked. Otherwise
# the session uses the operator's signed-in subscription (OS keyring via
# EVALS_OPERATOR_DBUS and, when present, ~/.gemini/oauth_creds.json, never
# settings.json, plugins, or hooks). The bundle installs locally with no hooks.
adapter_install() { # $1 bundle dir, or "" for the none arm
  lab_home_is_isolated || return 1
  _agy_use_keyring=0
  local seeded=0
  if [ -f "$HOME/.eval-env" ] || [ -f "$HOME/.gemini/oauth_creds.json" ]; then
    seeded=1
  fi
  if [ "$seeded" -eq 0 ]; then
    local op_gem="${EVALS_OPERATOR_HOME:-}/.gemini"
    if [ -f "$op_gem/oauth_creds.json" ]; then
      mkdir -p "$HOME/.gemini" || return 1
      cp "$op_gem/oauth_creds.json" "$HOME/.gemini/oauth_creds.json" \
        && chmod 0600 "$HOME/.gemini/oauth_creds.json" || return 1
      if [ -f "$op_gem/google_accounts.json" ]; then
        cp "$op_gem/google_accounts.json" "$HOME/.gemini/google_accounts.json" \
          && chmod 0600 "$HOME/.gemini/google_accounts.json" || return 1
      fi
    fi
    if [ -n "${EVALS_OPERATOR_DBUS:-}" ]; then
      _agy_use_keyring=1
    fi
  fi
  [ -n "${1:-}" ] || return 0
  local p="$HOME/.eval-plugin/eval-bundle"
  rm -rf "$HOME/.eval-plugin" && mkdir -p "$p" || return 1
  cp -R "$1/." "$p/" || return 1
  mkdir -p "$p/.antigravity-plugin" || return 1
  printf '{"name": "eval-bundle", "version": "0.0.0"}\n' > "$p/.antigravity-plugin/plugin.json"
  timeout_s=120 lab_exec AGY_CLI_DISABLE_AUTO_UPDATE=true -- agy plugin install "$p" \
    >> "${errlog:-/dev/null}" 2>&1
}

_agy_exec() { # $1 work dir, then agy arguments
  local wd="$1"; shift
  local env_extra=(AGY_CLI_DISABLE_AUTO_UPDATE=true)
  if [ "$_agy_use_keyring" -eq 1 ] && [ -n "${EVALS_OPERATOR_DBUS:-}" ]; then
    env_extra+=(DBUS_SESSION_BUS_ADDRESS="$EVALS_OPERATOR_DBUS")
  fi
  local extra=()
  [ -n "${model:-}" ] && extra+=(--model "$model")
  ( cd "$wd" && lab_exec "${env_extra[@]}" -- \
      agy --output-format stream-json ${extra[@]+"${extra[@]}"} "$@" </dev/null )
}

adapter_run_behavioral() { # $1 work dir $2 prompt file $3 stream
  _agy_exec "$1" --mode accept-edits --print="$(cat "$2")" > "$3" 2>> "${errlog:-/dev/null}"
}

adapter_run_activation() { # $1 work dir $2 prompt $3 stream
  _agy_exec "$1" --mode plan --print="$2" > "$3" 2>> "${errlog:-/dev/null}"
}

# A skill counts as loaded when a step names it, or a file-read tool reads a
# SKILL.md (its parent directory is the skill name). Handles both agy 1.5+
# (step_type="tool", tool_info.parameters.Path) and legacy step_type="tool_call".
adapter_chain() {
  lab_json_events "$1" | jq -r 'select(.event == "step_update") | .step_update
    | ((.skill_name // empty | strings),
       (select((.step_type == "tool" or .step_type == "tool_call")
               and (.tool_name == "view_file" or .tool_name == "read_file"))
        | (.path // .tool_info.parameters.Path // .tool_info.parameters.path // .tool_info.parameters.AbsolutePath // empty)
        | strings | select(endswith("/SKILL.md")) | split("/") | .[-2]))' | awk '!seen[$0]++'
}

adapter_ran() {
  [ "$(lab_json_events "$1" | jq -s 'any(.[];
    (.event == "result" and (.result.status // "") != "ERROR" and ((.result.num_turns // 0) > 0))
    or (.event == "step_update" and .step_update.step_type == "agent_response"))')" = true ]
}

adapter_output_tokens() {
  lab_json_events "$1" | jq -s -r '[.[] | select(.event == "result") | .result.usage.output_tokens // empty | numbers] | last // empty'
}

adapter_tool_calls() {
  lab_json_events "$1" | jq -s '[.[] | select(.event == "step_update") | .step_update
    | select((.step_type == "tool" or .step_type == "tool_call") and .state == "DONE") | .step_index] | unique | length'
}

# Count completed agent_response steps (actual model turns) when present; fall
# back to result.num_turns for streams that report only a summary turn count.
adapter_turns() {
  lab_json_events "$1" | jq -s -r '
    ([.[] | select(.event == "step_update") | .step_update
      | select(.step_type == "agent_response" and .state == "DONE") | .step_index] | unique | length) as $steps
    | if $steps > 0 then $steps
      else ([.[] | select(.event == "result") | .result.num_turns // empty | numbers] | last // 0)
      end'
}

adapter_session_model() {
  lab_json_events "$1" | jq -r 'select(.event == "init") | .init.model // empty' | head -n 1
}
