#!/usr/bin/env bash
# Antigravity CLI adapter. Sourced by evals/bin/* after lib/common.sh,
# lib/home-env.sh, and lib/stream-text.sh, with HOME already pointing at the
# run's isolated home. See evals/README.md for the adapter contract.

adapter_name=antigravity
runnable=no
runnable_reason="plugin install and stream-json shape are not yet verified against a live CLI"

adapter_check() { command -v agy >/dev/null 2>&1; }

adapter_version() { agy --version 2>/dev/null | head -n 1; }

# The account token lives in the operator's secret store, which the isolated
# session cannot reach; credentials come only from the eval credential seed.
# The bundle is installed as a local plugin with a manifest and no hooks.
adapter_install() { # $1 bundle dir, or "" for the none arm
  lab_home_is_isolated || return 1
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
  local extra=()
  [ -n "${model:-}" ] && extra+=(--model "$model")
  ( cd "$wd" && lab_exec AGY_CLI_DISABLE_AUTO_UPDATE=true -- \
      agy --output-format stream-json ${extra[@]+"${extra[@]}"} "$@" )
}

adapter_run_behavioral() { # $1 work dir $2 prompt file $3 stream
  _agy_exec "$1" --mode accept-edits --print="$(cat "$2")" > "$3" 2>> "${errlog:-/dev/null}"
}

adapter_run_activation() { # $1 work dir $2 prompt $3 stream
  _agy_exec "$1" --mode plan --print="$2" > "$3" 2>> "${errlog:-/dev/null}"
}

# A skill counts as loaded when a step names it, or a file-view tool reads a
# SKILL.md (its parent directory is the skill name).
adapter_chain() {
  lab_json_events "$1" | jq -r 'select(.event == "step_update") | .step_update
    | ((.skill_name // empty | strings),
       (select(.step_type == "tool_call" and (.tool_name == "view_file" or .tool_name == "read_file"))
        | .path // empty | strings | select(endswith("/SKILL.md")) | split("/") | .[-2]))' | awk '!seen[$0]++'
}

adapter_ran() {
  [ "$(lab_json_events "$1" | jq -s 'any(.[]; .event == "result"
    or (.event == "step_update" and .step_update.step_type == "agent_response"))')" = true ]
}

adapter_output_tokens() {
  lab_json_events "$1" | jq -s -r '[.[] | select(.event == "result") | .result.usage.output_tokens // empty | numbers] | last // empty'
}

adapter_tool_calls() {
  lab_json_events "$1" | jq -s '[.[] | select(.event == "step_update") | .step_update
    | select(.step_type == "tool_call" and .state == "DONE") | .step_index] | unique | length'
}

adapter_turns() {
  lab_json_events "$1" | jq -s -r '[.[] | select(.event == "result") | .result.num_turns // empty | numbers] | last // 0'
}

adapter_session_model() {
  lab_json_events "$1" | jq -r 'select(.event == "init") | .init.model // empty' | head -n 1
}
