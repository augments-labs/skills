#!/usr/bin/env bash
# Fake harness adapter for the offline suites, loaded with
# EVALS_HARNESS_DIR=evals/lib/tests/fake-cli and --harness fake. It drives a
# scripted agent ($FAKE_AGENT) through the same isolated session as a real
# adapter (lab_exec: cleared environment, throwaway HOME, timeout), so the
# runners are exercised end to end without any agent CLI.
#
# The scripted agent is called as: AGENT KIND WORKDIR PROMPT BUNDLE
#   KIND     behavioral | followup | activation
#   PROMPT   the prompt file (behavioral) or the message text (followup,
#            activation)
#   BUNDLE   the installed copy of the bundle, or "" for the none arm
# A behavioral session with follow-ups calls it once more per follow-up, in
# the same home and work tree, appending to the same stream.
# Its stdout is the stream, one record per line:
#   MODEL <id> · SKILL <name> · TOOL <name> · TURN · TOKENS <n> · TEXT <answer>
# Its exit status is the session's (124 reads as a timeout); text on stderr
# goes to the run's stderr log (where a refusal is detected).
#
# FAKE_RUNNABLE=no marks the adapter unverified; FAKE_CLI_MISSING=1 makes
# adapter_check fail; FAKE_INSTALL_FAIL=1 makes the install fail;
# FAKE_FOLLOWUPS=no makes the adapter refuse follow-ups; FAKE_LAUNCH_LOG names
# a file that gets one line per agent call.

adapter_name=fake
runnable="${FAKE_RUNNABLE:-yes}"
runnable_reason="${FAKE_RUNNABLE_REASON:-the fake adapter was marked unverified by the test}"

_fake_bundle=""

adapter_check() { [ "${FAKE_CLI_MISSING:-0}" != 1 ]; }

adapter_version() { echo "fake 1.0"; }

adapter_install() { # $1 bundle dir, or "" for the none arm
  lab_home_is_isolated || return 1
  [ "${FAKE_INSTALL_FAIL:-0}" != 1 ] || return 1
  _fake_bundle=""
  if [ -n "${1:-}" ]; then
    _fake_bundle="$HOME/.fake-bundle"
    rm -rf "$_fake_bundle" && cp -R "$1" "$_fake_bundle" || return 1
  fi
}

_fake_exec() { # $1 kind $2 work dir $3 prompt $4 stream
  local kind="$1" wd="$2" prompt="$3" stream="$4"
  if [ -n "${FAKE_LAUNCH_LOG:-}" ]; then
    printf 'launch kind=%s home=%s bundle=%s\n' "$kind" "$HOME" "${_fake_bundle:--}" >> "$FAKE_LAUNCH_LOG"
  fi
  if [ "$kind" = followup ]; then
    _fake_agent "$kind" "$wd" "$prompt" >> "$stream" 2>> "${errlog:-/dev/null}"
  else
    _fake_agent "$kind" "$wd" "$prompt" > "$stream" 2>> "${errlog:-/dev/null}"
  fi
}

_fake_agent() { # $1 kind $2 work dir $3 prompt
  ( cd "$2" && lab_exec FAKE_STATE="${FAKE_STATE:-}" -- \
      "${FAKE_AGENT:?FAKE_AGENT must name the scripted agent}" "$1" "$2" "$3" "$_fake_bundle" )
}

adapter_run_behavioral() { # $1 work dir $2 prompt file $3 stream [$4 follow-ups file]
  local start="$SECONDS"
  _fake_exec behavioral "$1" "$2" "$3" || return $?
  [ -z "${4:-}" ] || lab_each_followup "$4" "$start" _fake_followup "$1" "$3"
}

_fake_followup() { _fake_exec followup "$1" "$3" "$2"; } # $1 work dir $2 stream $3 message

adapter_supports_followups() { [ "${FAKE_FOLLOWUPS:-yes}" = yes ]; }

adapter_run_activation() { _fake_exec activation "$1" "$2" "$3"; }

adapter_chain() { awk '$1 == "SKILL" && NF > 1 && !seen[$2]++ { print $2 }' "$1" 2>/dev/null; }

adapter_ran() { grep -q '^TURN' "$1" 2>/dev/null; }

adapter_output_tokens() { awk '$1 == "TOKENS" { n += $2; s = 1 } END { if (s) print n }' "$1" 2>/dev/null; }

adapter_tool_calls() { awk '$1 == "TOOL" { n++ } END { print n + 0 }' "$1" 2>/dev/null; }

adapter_turns() { awk '$1 == "TURN" { n++ } END { print n + 0 }' "$1" 2>/dev/null; }

adapter_session_model() { awk '$1 == "MODEL" { print $2; exit }' "$1" 2>/dev/null; }
