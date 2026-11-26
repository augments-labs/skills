# Turns one harness hook event into a normalized check, and the verdict back
# into the harness's answer. Sourced by the hook entry scripts.
#
# Harnesses and their contracts:
#   claude-code  stdin {tool_name, tool_input.command | .file_path, cwd};
#                deny = exit 2 with the reason on stderr, allow = exit 0.
#   codex        same fields and answer; shell tools may send command as an
#                array, cmd, and workdir; apply_patch names files in headers.
#   antigravity  stdin {toolCall.name, toolCall.args, cwd, hookEventName};
#                answer on stdout: {"decision":"deny","reason":...} or {}.
#                Never answer "allow": that would approve the call outright.
#
# Devin also loads a plugin's hooks/hooks.json and hooks.json, with its own
# tool names and answers. These hooks are not adapted to it, so they allow
# every call when Devin runs them (it sets DEVIN_PROJECT_DIR for hooks).

# shellcheck source=common.sh
. "$AUG_LIB/common.sh"
# shellcheck source=walk.sh
. "$AUG_LIB/walk.sh"
# shellcheck source=git.sh
. "$AUG_LIB/git.sh"
# shellcheck source=checks.sh
. "$AUG_LIB/checks.sh"

AUG_SHELL_TOOLS=" Bash exec_command shell local_shell shell_command container.exec run_command "
AUG_EDIT_TOOLS=" Edit Write MultiEdit NotebookEdit apply_patch write_to_file replace_file_content multi_replace_file_content delete_file code_action file_change edit_notebook write_blob move delete_directory "

# aug_quote_join: AUG_COMMAND = AUG_ARR quoted for the shell, space-separated.
aug_quote_join() {
  local a q="'" out=""
  for a in ${AUG_ARR[@]+"${AUG_ARR[@]}"}; do
    out="$out${out:+ }'${a//$q/$q\\$q$q}'"
  done
  AUG_COMMAND="$out"
}

aug_add_lines() { # TEXT: appends each non-empty line to AUG_PATHS
  local rest="$1" line
  while [ -n "$rest" ]; do
    line="${rest%%"$AUG_NL"*}"
    case "$rest" in *"$AUG_NL"*) rest="${rest#*"$AUG_NL"}" ;; *) rest="" ;; esac
    [ -n "$line" ] && AUG_PATHS[${#AUG_PATHS[@]}]="$line"
  done
}

aug_set_cwd() { # DIR [BASE]
  local d="$1"
  [ -n "$d" ] || return 1
  aug_native_path "$d"; d="$REPLY"
  case "$d" in
    /*) aug_normpath "$d" ;;
    *) [ -n "${2-}" ] || return 1; aug_normpath "$2/$d" ;;
  esac
  AUG_CWD="$REPLY"
}

# aug_parse_event HARNESS INPUT: sets AUG_EVENT, AUG_TOOL, AUG_KIND (shell,
# edit, or ""), AUG_COMMAND, AUG_PATHS[], AUG_CWD. Returns 1 on bad JSON.
aug_parse_event() {
  local harness="$1" input="$2" v
  AUG_EVENT="" AUG_TOOL="" AUG_KIND="" AUG_COMMAND="" AUG_PATHS=() AUG_CWD=""
  case "$harness" in
    antigravity)
      aug_json_load "toolCall.name hookEventName cwd toolCall.args.CommandLine toolCall.args.Cwd" <<<"$input" || return 1
      aug_jget hookEventName; AUG_EVENT="$REPLY"
      aug_jget toolCall.name; AUG_TOOL="$REPLY"
      aug_jget cwd; aug_set_cwd "$REPLY"
      aug_jget toolCall.args.Cwd && aug_set_cwd "$REPLY" "$AUG_CWD"
      if aug_jget toolCall.args.CommandLine; then
        AUG_KIND=shell AUG_COMMAND="$REPLY"
      else
        case "$AUG_EDIT_TOOLS" in *" $AUG_TOOL "*) AUG_KIND=edit ;; esac
        case "$AUG_TOOL" in *[Ww]rite*|*[Rr]eplace*|*[Ee]dit*|*[Dd]elete*|*[Mm]ove*|*[Rr]ename*|*[Cc]reate*|*[Cc]hange*) AUG_KIND=edit ;; esac
        if [ "$AUG_KIND" = edit ]; then
          v="$(AUG_JMODE=keys AUG_JPATH=toolCall.args. AUG_JKEY='([Ff]ile|[Pp]ath|[Dd]irectory|[Ss]ource|[Dd]estination)$' awk -f "$AUG_LIB/json.awk" <<<"$input")"
          aug_add_lines "$v"
        fi
      fi
      ;;
    *)
      aug_json_load "tool_name hook_event_name cwd tool_input.command tool_input.cmd tool_input.workdir tool_input.file_path tool_input.notebook_path" <<<"$input" || return 1
      aug_jget hook_event_name; AUG_EVENT="$REPLY"
      aug_jget tool_name; AUG_TOOL="$REPLY"
      aug_jget cwd; aug_set_cwd "$REPLY" || { [ "$harness" = claude-code ] && aug_set_cwd "$PWD"; }
      aug_jget tool_input.workdir && aug_set_cwd "$REPLY" "$AUG_CWD"
      if aug_jget tool_input.command || aug_jget tool_input.cmd; then
        AUG_COMMAND="$REPLY"
      else
        aug_jarray tool_input.command
        [ "${#AUG_ARR[@]}" -gt 0 ] || aug_jarray tool_input.cmd
        [ "${#AUG_ARR[@]}" -gt 0 ] && aug_quote_join
      fi
      case "$AUG_SHELL_TOOLS" in *" $AUG_TOOL "*) AUG_KIND=shell ;; esac
      [ -z "$AUG_TOOL" ] && [ -n "$AUG_COMMAND" ] && AUG_KIND=shell
      case "$AUG_EDIT_TOOLS" in *" $AUG_TOOL "*) [ -n "$AUG_KIND" ] || AUG_KIND=edit ;; esac
      aug_jget tool_input.file_path && AUG_PATHS[${#AUG_PATHS[@]}]="$REPLY"
      aug_jget tool_input.notebook_path && AUG_PATHS[${#AUG_PATHS[@]}]="$REPLY"
      ;;
  esac
  # apply_patch can arrive as its own tool or inside a shell command.
  case "$input" in
    *'*** '*)
      v="$(AUG_JMODE=patch AUG_JPATH= awk -f "$AUG_LIB/json.awk" <<<"$input")"
      aug_add_lines "$v"
      ;;
  esac
  return 0
}

# aug_hook_main HOOK [HARNESS] < event: answers for HARNESS (detected from
# the input when omitted) and returns the process exit status to use.
aug_hook_main() {
  local hook="$1" harness="${2-}" input verdict=0 what
  input="$(cat)"
  # Under Devin: allow silently (see the header).
  [ -z "${DEVIN_PROJECT_DIR-}" ] || return 0
  if [ -z "$harness" ]; then
    case "$input" in *'"toolCall"'*) harness=antigravity ;; *) harness=claude-code ;; esac
  fi
  case "$harness" in
    claude-code|codex|antigravity) ;;
    *) echo "$hook: unknown harness '$harness' (use claude-code, codex, or antigravity)" >&2; return 64 ;;
  esac
  if ! aug_parse_event "$harness" "$input"; then
    echo "$hook: could not parse the hook input; allowing" >&2
  elif [ -n "$AUG_EVENT" ] && [ "$AUG_EVENT" != PreToolUse ]; then
    :
  else
    if [ -n "$AUG_COMMAND" ] && [ "$AUG_KIND" != edit ]; then
      aug_run_checks "$hook" shell || verdict=1
      what="command"
    fi
    if [ "$verdict" -eq 0 ] && [ "${#AUG_PATHS[@]}" -gt 0 ]; then
      aug_run_checks "$hook" edit || verdict=1
      what="edit"
    fi
  fi
  if [ "$verdict" -eq 0 ]; then
    [ "$harness" = antigravity ] && printf '{}\n'
    return 0
  fi
  REPLY="$hook blocked this $what: $AUG_REASON. If it is really needed, ask the user to do it themselves."
  if [ "$harness" = antigravity ]; then
    aug_json_escape "$REPLY"
    printf '{"decision":"deny","reason":"%s"}\n' "$REPLY"
    return 0
  fi
  printf '%s\n' "$REPLY" >&2
  return 2
}
