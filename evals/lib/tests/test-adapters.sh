#!/usr/bin/env bash
# The three harness adapters, offline: the contract, stream parsers on
# recorded fixtures, and install/launch isolation against fake CLIs that log
# their argv and environment. No real agent CLI runs (the tripwire is on PATH).
. "$(dirname "${BASH_SOURCE[0]}")/testlib.bash"

STREAMS="$TL_FIX/streams"
HARNESSES=(claude-code codex antigravity)

# Runs a command with one adapter loaded, in a subshell.
with_adapter() { # $1 harness, rest: command
  (
    . "$TL_EVALS/lib/common.sh"; . "$TL_EVALS/lib/home-env.sh"; . "$TL_EVALS/lib/stream-text.sh"
    harness="$1"; shift
    load_adapter "$harness" || exit 2
    "$@"
  )
}

# --- the contract -------------------------------------------------------------
for h in "${HARNESSES[@]}"; do
  check "$h defines the adapter contract" q with_adapter "$h" true
done
eq "claude-code is runnable" yes "$(with_adapter claude-code eval 'echo $runnable')"
eq "codex is marked unverified" no "$(with_adapter codex eval 'echo $runnable')"
eq "antigravity is runnable" yes "$(with_adapter antigravity eval 'echo $runnable')"
check "an unverified adapter states why" test -n "$(with_adapter codex eval 'echo $runnable_reason')"
check "only the three adapters ship" test "$(cd "$TL_EVALS/harnesses" && ls | paste -sd' ')" = "antigravity.sh claude-code.sh codex.sh"
refute "an unknown harness does not load" q with_adapter nope true
refute "a harness name cannot be a path" q with_adapter ../lib/common true

# --- stream parsers -----------------------------------------------------------
_parse() { # $1 stream
  local r=n
  adapter_ran "$1" && r=y
  printf '%s|%s|%s|%s|%s|%s\n' "$(adapter_chain "$1" | paste -sd, -)" "$r" "$(adapter_output_tokens "$1")" \
    "$(adapter_tool_calls "$1")" "$(adapter_turns "$1")" "$(adapter_session_model "$1")"
}
# chain | ran | output tokens | tool calls | turns | model
eq "claude-code: a skill load, tokens, tools, turns, model" "demo-skill|y|30|2|3|fixture-model-1" "$(with_adapter claude-code _parse "$STREAMS/claude-code.ndjson")"
eq "claude-code: no skill load" "|y|7|0|1|fixture-model-1" "$(with_adapter claude-code _parse "$STREAMS/claude-code-negative.ndjson")"
eq "codex: a SKILL.md read is a load, deduped; tokens summed over turns" "demo-skill|y|15|3|2|" "$(with_adapter codex _parse "$STREAMS/codex.ndjson")"
eq "codex: no skill load" "|y|4|1|1|" "$(with_adapter codex _parse "$STREAMS/codex-negative.ndjson")"
eq "antigravity: named and file-read loads, unique DONE tool steps" "demo-skill|y|20|2|1|fixture-model-2" "$(with_adapter antigravity _parse "$STREAMS/antigravity.ndjson")"
eq "antigravity: no skill load" "|y||1|1|" "$(with_adapter antigravity _parse "$STREAMS/antigravity-negative.ndjson")"
# Live agy 1.5+ stream shape: step_type="tool", tool_info.parameters.Path,
# multi-step agent_response turns, and ERROR result with num_turns=0.
cat > "$TL_TMP/agy-v15.ndjson" <<'EOF'
{"event":"init","conversation_id":"c1","init":{"cwd":"/tmp/work","tools":["read_file","edit_file"]}}
{"event":"step_update","step_update":{"conversation_id":"c1","step_index":0,"state":"DONE","step_type":"user_input"}}
{"event":"step_update","step_update":{"conversation_id":"c1","step_index":1,"state":"DONE","step_type":"agent_response","usage":{"output_tokens":100}}}
{"event":"step_update","step_update":{"conversation_id":"c1","step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"read_file","tool_info":{"name":"read_file","parameters":{"Path":"/tmp/home/.gemini/config/plugins/eval-bundle/skills/demo-skill/SKILL.md"}}}}
{"event":"step_update","step_update":{"conversation_id":"c1","step_index":2,"state":"DONE","step_type":"tool","tool_name":"read_file","tool_info":{"name":"read_file","parameters":{"Path":"/tmp/home/.gemini/config/plugins/eval-bundle/skills/demo-skill/SKILL.md"}}}}
{"event":"step_update","step_update":{"conversation_id":"c1","step_index":3,"state":"DONE","step_type":"tool","tool_name":"edit_file","tool_info":{"name":"edit_file","parameters":{"Path":"/tmp/work/app.txt"}}}}
{"event":"step_update","step_update":{"conversation_id":"c1","step_index":4,"state":"DONE","step_type":"agent_response","text_delta":"done","usage":{"output_tokens":50}}}
{"event":"result","result":{"conversation_id":"c1","status":"SUCCESS","response":"done","num_turns":1,"usage":{"output_tokens":150}}}
EOF
eq "antigravity: agy 1.5+ tool/Path skill load, tool calls, and model turns" \
  "demo-skill|y|150|2|2|" "$(with_adapter antigravity _parse "$TL_TMP/agy-v15.ndjson")"
cat > "$TL_TMP/agy-auth-err.ndjson" <<'EOF'
{"event":"result","result":{"conversation_id":"","status":"ERROR","response":"","error":"authentication failed or timed out","num_turns":0,"usage":{"output_tokens":0}}}
EOF
refute "antigravity: ERROR result with 0 turns is not a model turn" with_adapter antigravity adapter_ran "$TL_TMP/agy-auth-err.ndjson"
check "antigravity: authentication error is detected as a refusal" \
  with_adapter antigravity lab_refusal "$TL_TMP/agy-auth-err.ndjson" /dev/null
: > "$TL_TMP/empty.ndjson"
printf 'not json\n{"type":"assistant"\n' > "$TL_TMP/garbage.ndjson"
for h in "${HARNESSES[@]}"; do
  refute "$h: an empty stream is no model turn" with_adapter "$h" adapter_ran "$TL_TMP/empty.ndjson"
  refute "$h: a garbage stream is no model turn" with_adapter "$h" adapter_ran "$TL_TMP/garbage.ndjson"
  eq "$h: a garbage stream loads nothing" "" "$(with_adapter "$h" adapter_chain "$TL_TMP/garbage.ndjson")"
done

# --- answer text --------------------------------------------------------------
. "$TL_EVALS/lib/stream-text.sh"
for h in "${HARNESSES[@]}"; do
  eq "$h: the final answer is extracted" "done: the fix is in" "$(lab_extract_stream_text "$STREAMS/$h.ndjson" "$h")"
  eq "$h: the negative answer is extracted" "no skill needed" "$(lab_extract_stream_text "$STREAMS/$h-negative.ndjson" "$h")"
done
refute "a stream is read only as its own harness" q lab_extract_stream_text "$STREAMS/claude-code.ndjson" codex
refute "an empty stream has no answer" q lab_extract_stream_text "$TL_TMP/empty.ndjson" claude-code
eq "a plain-text stream is returned as-is" "TEXT hi" "$(printf 'TEXT hi\n' > "$TL_TMP/plain"; lab_extract_stream_text "$TL_TMP/plain" fake)"

# --- install and launch isolation ---------------------------------------------
bin="$TL_TMP/bin"
mkdir -p "$bin"
for c in claude codex agy; do ln -s "$TL_FIX/harnesses/fake-cli.sh" "$bin/$c"; done
op="$EVALS_OPERATOR_HOME"
mkdir -p "$op/.claude" "$op/.codex" "$op/.gemini/antigravity-cli"
printf '{"token": "operator-claude"}\n' > "$op/.claude/.credentials.json"
printf '{"hooks": {"Stop": [{"command": "rm -rf /"}]}}\n' > "$op/.claude/settings.json"
printf 'operator instructions\n' > "$op/.claude/CLAUDE.md"
printf '{"token": "operator-codex"}\n' > "$op/.codex/auth.json"
printf 'notify = ["rm", "-rf", "/"]\n' > "$op/.codex/config.toml"
printf '{"token": "operator-gemini"}\n' > "$op/.gemini/oauth_creds.json"
printf '{"hooks": {"PreToolUse": []}}\n' > "$op/.gemini/antigravity-cli/settings.json"
cp "$op/.claude/settings.json" "$TL_TMP/settings.orig"
bundle="$TL_TMP/bundle"
mkdir -p "$bundle"
( . "$TL_EVALS/lib/common.sh"; build_bundle "$TL_FIX/repo/skills/in-progress/demo-skill" demo-skill "$bundle" )
eq "build_bundle copies SKILL.md and support dirs only" "skills/demo-skill/SKILL.md skills/demo-skill/references/guide.md" \
  "$(cd "$bundle" && find . -type f | sed 's|^\./||' | sort | paste -sd' ')"

# One isolated session: seed, install, launch. Leaves the home in place (under
# $TL_TMP) so the suite can inspect it.
_session() { # $1 base $2 bundle ("" for none) $3 kind
  local base="$1" b="$2" kind="$3" wd="$1/work"
  eval "$(lab_home_env "$base")" || exit 1
  export LAB_RUN_BASE EVALS_OPERATOR_HOME EVALS_OPERATOR_DBUS HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR TMPDIR
  errlog="$base/stderr.log"; timeout_s=30; maxturns=4
  lab_seed_credentials "$harness" || exit 1
  adapter_install "$b" || exit 1
  (cd "$HOME" && find . \( -type f -o -type l \) | sed 's|^\./||' | sort) > "$base/home-files"
  mkdir -p "$wd"
  printf 'Rename the widget.\n' > "$base/prompt.txt"
  if [ "$kind" = behavioral ]; then
    adapter_run_behavioral "$wd" "$base/prompt.txt" "$base/stream"
  else
    adapter_run_activation "$wd" "Rename the widget." "$base/stream"
  fi
}
session() { # $1 harness $2 name $3 bundle $4 kind [$5 model]
  rm -f "$bin"/*.argv "$bin"/*.env "$bin"/*.stream
  case "$1" in claude-code) cli=claude ;; codex) cli=codex ;; antigravity) cli=agy ;; esac
  cp "$STREAMS/$1.ndjson" "$bin/$cli.stream"
  sbase="$TL_TMP/sessions/$2"
  EVALS_TEST_SECRET=operator-secret model="${5:-}" PATH="$bin:$PATH" with_adapter "$1" _session "$sbase" "$3" "$4"
  src=$?
  shome="$sbase/home"
}
argv_has() { grep -qxF -- "$2" "$bin/$1.argv"; }
# The argument that follows $2 in the first logged call.
argv_after() { awk -v k="$2" 'p { print; exit } $0 == k { p = 1 }' "$bin/$1.argv"; }

# claude-code
session claude-code cc-full "$bundle" behavioral
eq "claude-code: a session exits 0" 0 "$src"
check "claude-code: the stream is written" cmp -s "$sbase/stream" "$STREAMS/claude-code.ndjson"
eq "claude-code: the home holds credentials, hook-off settings, and the bundle only" \
  ".claude/.credentials.json .claude/settings.json .eval-plugin/.claude-plugin/plugin.json .eval-plugin/skills/demo-skill/SKILL.md .eval-plugin/skills/demo-skill/references/guide.md" \
  "$(paste -sd' ' "$sbase/home-files")"
eq "claude-code: settings turn every hook off" '{"disableAllHooks": true}' "$(cat "$shome/.claude/settings.json")"
eq "claude-code: the credential file is private" 600 "$(stat -c %a "$shome/.claude/.credentials.json" 2>/dev/null || stat -f %Lp "$shome/.claude/.credentials.json")"
check "claude-code: the operator settings are untouched" cmp -s "$op/.claude/settings.json" "$TL_TMP/settings.orig"
eq "claude-code: the prompt is passed" "Rename the widget." "$(argv_after claude -p)"
eq "claude-code: the bundle is a plugin dir" "$shome/.eval-plugin" "$(argv_after claude --plugin-dir)"
eq "claude-code: stream-json output" stream-json "$(argv_after claude --output-format)"
eq "claude-code: edits are accepted" acceptEdits "$(argv_after claude --permission-mode)"
refute "claude-code: no model flag by default" argv_has claude --model
contains "claude-code: CLAUDE_CONFIG_DIR is the isolated config" "$bin/claude.env" "CLAUDE_CONFIG_DIR=$shome/.claude"
contains "claude-code: HOME is the isolated home" "$bin/claude.env" "HOME=$shome"
lacks "claude-code: the operator environment is cleared" "$bin/claude.env" "EVALS_TEST_SECRET"
lacks "claude-code: the operator home is never named" "$bin/claude.env" "EVALS_OPERATOR_HOME"
contains "claude-code: no session bus" "$bin/claude.env" "DBUS_SESSION_BUS_ADDRESS=unix:path=$sbase/run/no-session-bus"
session claude-code cc-none "" activation some-model
refute "claude-code: the none arm installs no plugin" argv_has claude --plugin-dir
check "claude-code: the none arm home has no plugin" test ! -e "$shome/.eval-plugin"
eq "claude-code: activation caps turns" 4 "$(argv_after claude --max-turns)"
eq "claude-code: activation is limited to read-only tools" "Skill,Read,Glob,Grep" "$(argv_after claude --tools)"
eq "claude-code: --model is passed" some-model "$(argv_after claude --model)"

# codex
session codex cx-full "$bundle" behavioral
eq "codex: a session exits 0" 0 "$src"
eq "codex: the home holds auth.json and the skills only" \
  ".codex/auth.json .codex/skills/demo-skill/SKILL.md .codex/skills/demo-skill/references/guide.md" \
  "$(paste -sd' ' "$sbase/home-files")"
check "codex: no config.toml is copied" test ! -e "$shome/.codex/config.toml"
eq "codex: exec mode" exec "$(head -n 1 "$bin/codex.argv")"
check "codex: JSON events" argv_has codex --json
eq "codex: runs in the work tree" "$sbase/work" "$(argv_after codex -C)"
eq "codex: the prompt follows --full-auto" "Rename the widget." "$(argv_after codex --full-auto)"
contains "codex: CODEX_HOME is the isolated home" "$bin/codex.env" "CODEX_HOME=$shome/.codex"
lacks "codex: the operator environment is cleared" "$bin/codex.env" "EVALS_TEST_SECRET"
session codex cx-none "" activation
check "codex: the none arm installs no skills" test ! -e "$shome/.codex/skills"
eq "codex: activation is read-only" read-only "$(argv_after codex -s)"

# antigravity
EVALS_OPERATOR_DBUS="unix:path=/run/user/1000/bus" session antigravity agy-full "$bundle" behavioral
eq "antigravity: a session exits 0" 0 "$src"
eq "antigravity: the bundle is installed as a plugin" "plugin install $shome/.eval-plugin/eval-bundle" "$(awk 'NR <= 3' "$bin/agy.argv" | paste -sd' ')"
check "antigravity: the plugin has a manifest" test -f "$shome/.eval-plugin/eval-bundle/.antigravity-plugin/plugin.json"
check "antigravity: the plugin carries no hooks" test -z "$(find "$shome/.eval-plugin" -name 'hooks*')"
check "antigravity: operator oauth_creds is copied when unseeded" test -f "$shome/.gemini/oauth_creds.json"
eq "antigravity: copied oauth_creds is private" 600 "$(stat -c %a "$shome/.gemini/oauth_creds.json" 2>/dev/null || stat -f %Lp "$shome/.gemini/oauth_creds.json")"
check "antigravity: operator settings.json is never copied" test ! -e "$shome/.gemini/antigravity-cli/settings.json"
contains "antigravity: unseeded subscription forwards operator keyring bus" "$bin/agy.env" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
eq "antigravity: the prompt is passed" "--print=Rename the widget." "$(grep -- '^--print=' "$bin/agy.argv")"
eq "antigravity: edits are accepted" accept-edits "$(argv_after agy --mode)"
lacks "antigravity: the operator environment is cleared" "$bin/agy.env" "EVALS_TEST_SECRET"
session antigravity agy-none "" activation
lacks "antigravity: the none arm installs nothing" "$bin/agy.argv" "plugin"
eq "antigravity: activation plans only" plan "$(argv_after agy --mode)"

# Seeded API key for antigravity overrides operator subscription auth and keeps D-Bus blocked.
mkdir -p "$EVALS_CREDENTIAL_SEED/antigravity"
printf 'GEMINI_API_KEY=seeded-gemini-key\n' > "$EVALS_CREDENTIAL_SEED/antigravity/.eval-env"
EVALS_OPERATOR_DBUS="unix:path=/run/user/1000/bus" session antigravity agy-seeded "$bundle" behavioral
check "antigravity: seeded API key skips operator oauth_creds" test ! -e "$shome/.gemini/oauth_creds.json"
contains "antigravity: seeded API key keeps session bus blocked" "$bin/agy.env" "DBUS_SESSION_BUS_ADDRESS=unix:path=$sbase/run/no-session-bus"
contains "antigravity: seeded API key reaches child env" "$bin/agy.env" "GEMINI_API_KEY=seeded-gemini-key"
rm -rf "$EVALS_CREDENTIAL_SEED/antigravity"

# The credential seed is copied into the home, private.
mkdir -p "$EVALS_CREDENTIAL_SEED/codex/.codex"
printf '{"token": "seeded"}\n' > "$EVALS_CREDENTIAL_SEED/codex/.codex/auth.json"
session codex cx-seeded "$bundle" behavioral
eq "a seeded credential wins over the operator's" '{"token": "seeded"}' "$(cat "$shome/.codex/auth.json")"
eq "a seeded credential is private" 600 "$(stat -c %a "$shome/.codex/auth.json" 2>/dev/null || stat -f %Lp "$shome/.codex/auth.json")"
rm -rf "$EVALS_CREDENTIAL_SEED/codex"

# --- refusal outside an isolated home -----------------------------------------
_unisolated() { HOME="$EVALS_OPERATOR_HOME"; unset LAB_RUN_BASE; adapter_install "$1"; }
for h in "${HARNESSES[@]}"; do
  refute "$h: install refuses a HOME that is not isolated" q with_adapter "$h" _unisolated "$bundle"
done
check "the refusals wrote nothing to the operator home" cmp -s "$op/.claude/settings.json" "$TL_TMP/settings.orig"
check "no plugin reached the operator home" test ! -e "$op/.eval-plugin"
refute "seeding refuses a HOME that is not isolated" q with_adapter codex eval 'HOME=$EVALS_OPERATOR_HOME; unset LAB_RUN_BASE; lab_seed_credentials codex'

# --- gates and versions -------------------------------------------------------
eq "the version comes from the CLI" "claude 0.0.0-fake" "$(PATH="$bin:$PATH" with_adapter claude-code adapter_version)"
_gate() { adapter_gate "$harness" "$1"; }
gate_rc() { local r=0; PATH="$1" with_adapter "$2" _gate "$3" > /dev/null 2>&1 || r=$?; echo "$r"; }
eq "a runnable adapter passes the gate" 0 "$(gate_rc "$bin:$PATH" claude-code 0)"
eq "antigravity passes the gate without --allow-unverified" 0 "$(gate_rc "$bin:$PATH" antigravity 0)"
eq "an unverified adapter is gated (exit 2)" 2 "$(gate_rc "$bin:$PATH" codex 0)"
eq "--allow-unverified opens the gate" 0 "$(gate_rc "$bin:$PATH" codex 1)"
mkdir -p "$TL_TMP/nocli" && ln -sf "$(command -v dirname)" "$TL_TMP/nocli/dirname"
eq "a missing CLI is exit 3" 3 "$(gate_rc "$TL_TMP/nocli" claude-code 0)"

tl_done
