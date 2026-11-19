#!/usr/bin/env bash
# The agent's answer text from a session stream. Sourced, never executed.
#
# Each JSON line is classified as a final answer, a whole message, or a text
# delta. The answer is the last final, else the last message, else the
# deltas joined. A stream with no JSON at all is returned as-is (the fake
# adapter and plain-text CLIs).

_LAB_STREAM_TEXT_JQ='
def txt:
  if type == "string" then .
  elif type == "array" then
    [.[] | select(type == "object" and .type == "text") | .text | strings] | join("")
  else "" end;
def cls:
  if .event == "result" and (.result | type) == "object"
     and (.result.response | type) == "string" then
    {h: "antigravity", k: "final", t: .result.response}
  elif .event == "step_update" and (.step_update | type) == "object"
     and .step_update.step_type == "agent_response"
     and (.step_update.text_delta | type) == "string" then
    {h: "antigravity", k: "delta", t: .step_update.text_delta}
  elif .type == "assistant" and (.message | type) == "object"
     and .message.role == "assistant" then
    {h: "claude", k: "message", t: (.message.content | txt)}
  elif .type == "result" and (.result | type) == "string" then
    {h: "claude", k: "final", t: .result}
  elif .type == "item.completed" and (.item | type) == "object"
     and .item.type == "agent_message" and (.item.text | type) == "string" then
    {h: "codex", k: "message", t: .item.text}
  else empty end;
[ split("\n")[] | fromjson? | objects | (cls)? | select(.t != "")
  | select($fam == "" or .h == $fam) ] as $r
| ([$r[] | select(.k == "final")] | last | .t?)
  // ([$r[] | select(.k == "message")] | last | .t?)
  // ([$r[] | select(.k == "delta") | .t] | if length > 0 then join("") else null end)
  // empty
'

lab_extract_stream_text() { # $1 stream [$2 harness]; prints the answer text
  local stream="${1:-}" harness="${2:-}" family objects text
  [ -s "$stream" ] || return 1
  case "$harness" in
    claude-code) family=claude ;;
    antigravity|codex) family="$harness" ;;
    *) family="" ;;
  esac
  objects="$(jq -R -s '[split("\n")[] | fromjson? | objects] | length' "$stream" 2>/dev/null)" || return 1
  if [ "$objects" = 0 ]; then
    cat "$stream"
    return 0
  fi
  text="$(jq -R -s -r --arg fam "$family" "$_LAB_STREAM_TEXT_JQ" "$stream" 2>/dev/null)" || return 1
  [ -n "$text" ] || return 1
  printf '%s\n' "$text"
}

# Every JSON object in a stream, one per line; non-JSON lines are dropped.
lab_json_events() { jq -cR 'fromjson? | objects' "$1" 2>/dev/null; }
