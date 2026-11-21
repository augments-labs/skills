#!/bin/sh
# Scripted agent for the fake adapter (fake-cli/fake.sh). Deterministic
# stand-in for a model: it "loads" demo-skill when the request matches the
# installed skill, edits the seeded work tree the way a model with or without
# the skill would, and prints the fake stream protocol on stdout.
#
# Called as: agent.sh KIND WORKDIR PROMPT BUNDLE (see fake.sh). Behavior can be
# steered by $FAKE_STATE/mode:
#   dead        print nothing (no model turn)
#   refuse      a provider refusal on stderr, exit 1
#   crash       one turn, then exit 3
#   sleep       one turn, then sleep past any test timeout
#   linger      activation: load the skill, then keep the session open
#   none-loads  report a skill load even with no bundle installed
#   sprawl      with a bundle, write an unrequested file on the typo task
#   parallel    briefly hold an active slot and record concurrency counts
# Every launch appends what it saw to $FAKE_STATE/launches.
kind="$1" wd="$2" prompt="$3" bundle="$4"
state="${FAKE_STATE:-}"
mode=""
if [ -n "$state" ] && [ -f "$state/mode" ]; then mode="$(cat "$state/mode")"; fi
if [ -n "$state" ]; then
  token=no
  [ -f "$HOME/.fake-token" ] && token=yes
  printf 'kind=%s home=%s pwd=%s wd=%s bundle=%s api_key=%s leaked=%s token_file=%s\n' \
    "$kind" "$HOME" "$(pwd -P)" "$wd" "${bundle:--}" "${FAKE_API_KEY:-}" "${EVALS_TEST_SECRET:-}" "$token" \
    >> "$state/launches"
  env | LC_ALL=C sort > "$state/env.$kind.$$" && mv -f "$state/env.$kind.$$" "$state/env.$kind"
  if [ -n "$bundle" ]; then
    (cd "$bundle" && find . -type f | LC_ALL=C sort) > "$state/bundle.$kind.$$" \
      && mv -f "$state/bundle.$kind.$$" "$state/bundle.$kind"
  fi
fi

case "$mode" in
  dead) exit 0 ;;
  refuse) echo "error: usage limit reached for this account" >&2; exit 1 ;;
  crash) echo "TURN"; exit 3 ;;
  sleep) echo "TURN"; sleep 30; exit 0 ;;
  parallel)
    if [ -n "$state" ]; then
      mkdir -p "$state/active"
      : > "$state/active/$$"
      sleep 0.4
      ls -1 "$state/active" 2>/dev/null | wc -l | tr -d ' ' >> "$state/concurrency"
      sleep 0.4
      rm -f "$state/active/$$"
    fi ;;
esac

skill_md=""
if [ -n "$bundle" ] && [ -f "$bundle/skills/demo-skill/SKILL.md" ]; then
  skill_md="$bundle/skills/demo-skill/SKILL.md"
fi
echo "MODEL fake-model-1"
echo "TURN"

if [ "$kind" = activation ]; then
  # Routing: load the skill when a word of 5+ letters from the request
  # appears in its description.
  desc=""
  [ -n "$skill_md" ] && desc="$(sed -n 's/^description: *//p' "$skill_md" | tr 'A-Z' 'a-z')"
  for w in $(printf '%s\n' "$prompt" | tr 'A-Z' 'a-z' | tr -c 'a-z\n' ' '); do
    [ "${#w}" -ge 5 ] || continue
    case "$desc" in
      *"$w"*)
        echo "SKILL demo-skill"
        if [ "$mode" = linger ]; then sleep 30; fi
        exit 0 ;;
    esac
  done
  echo "TEXT no skill needed"
  exit 0
fi

p="$(cat "$prompt")"
case "$p" in
  *candidate-description.txt*)
    # The description reviser: append the requests it was told were missed.
    cur="$(awk 'f { print; exit } $0 == "Current description:" { f = 1 }' "$prompt")"
    missed="$(sed -n 's/^- should load the skill, but did not: //p' "$prompt" | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 }')"
    printf '%s Covers requests like: %s.\n' "$cur" "$missed" > candidate-description.txt
    echo "TOOL Write"
    echo "TOKENS 40"
    echo "TEXT wrote candidate-description.txt"
    exit 0 ;;
esac

loaded=0
if [ -n "$skill_md" ]; then
  case "$p" in *widget*) loaded=1; echo "SKILL demo-skill" ;; esac
fi
if [ "$mode" = none-loads ] && [ -z "$bundle" ]; then echo "SKILL demo-skill"; fi

case "$p" in
  *"Rename the widget"*)
    echo "TOOL Read"
    echo "TOOL Edit"
    sed 's/oldWidget/newWidget/g' src/app.js > src/app.js.tmp && mv src/app.js.tmp src/app.js
    if [ "$loaded" = 1 ] && grep -q registry "$skill_md"; then
      echo "TOOL Edit"
      sed 's/oldWidget/newWidget/g' registry.txt > registry.txt.tmp && mv registry.txt.tmp registry.txt
    fi
    echo "TOKENS 120" ;;
  *"Fix the typo"*)
    echo "TOOL Edit"
    sed 's/Teh/The/' README.md > README.md.tmp && mv README.md.tmp README.md
    if [ "$mode" = sprawl ] && [ -n "$bundle" ]; then
      echo "TOOL Write"
      echo "notes" > NOTES.md
    fi
    echo "TOKENS 20" ;;
  *greeting*)
    echo "TOOL Edit"
    sed 's/"Hello"/"Hi"/' src/app.js > src/app.js.tmp && mv src/app.js.tmp src/app.js
    echo "TOKENS 30" ;;
esac
echo "TEXT done"
exit 0
