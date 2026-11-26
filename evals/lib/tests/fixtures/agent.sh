#!/bin/sh
# Scripted agent for the fake adapter (fake-cli/fake.sh). Deterministic
# stand-in for a model: it "loads" the installed skill when the request matches
# it, edits the seeded work tree the way a model with or without the skill
# would, and prints the fake stream protocol on stdout.
#
# Called as: agent.sh KIND WORKDIR PROMPT BUNDLE (see fake.sh). Behavior can be
# steered by $FAKE_STATE/mode:
#   dead        print nothing (no model turn)
#   refuse      a provider refusal on stderr, exit 1
#   refuse-activation  a provider refusal on activation sessions only
#   crash       one turn, then exit 3
#   crash-followup  a follow-up turn exits 3 (the first prompt runs normally)
#   sleep       one turn, then sleep past any test timeout
#   linger      activation: load the skill, then keep the session open
#   none-loads  report a skill load even with no bundle installed
#   sprawl      with a bundle, write an unrequested file on the typo task
#   parallel    briefly hold an active slot and record concurrency counts
#   drain       read stdin to EOF first, as an agent CLI in print mode does
#   skill-misnamed  a written skill's name differs from its directory
# Every launch appends what it saw to $FAKE_STATE/launches, and a follow-up
# appends its message (then a "--" line) to $FAKE_STATE/followups.
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
  drain) cat > /dev/null ;;
  dead) exit 0 ;;
  refuse) echo "error: usage limit reached for this account" >&2; exit 1 ;;
  refuse-activation)
    if [ "$kind" = activation ]; then echo "error: usage limit reached for this account" >&2; exit 1; fi ;;
  crash) echo "TURN"; exit 3 ;;
  crash-followup) if [ "$kind" = followup ]; then echo "TURN"; exit 3; fi ;;
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

skill_md="" skill_name=""
if [ -n "$bundle" ]; then
  for f in "$bundle"/skills/*/SKILL.md; do
    if [ -f "$f" ]; then skill_md="$f"; skill_name="$(basename "$(dirname "$f")")"; break; fi
  done
fi
echo "MODEL fake-model-1"
echo "TURN"

if [ "$kind" = followup ]; then
  # A follow-up in the same session: the work tree holds the earlier turns' edits.
  [ -n "$state" ] && printf '%s\n--\n' "$prompt" >> "$state/followups"
  case "$prompt" in
    *registry.txt*)
      echo "TOOL Edit"
      sed 's/oldWidget/newWidget/g' registry.txt > registry.txt.tmp && mv registry.txt.tmp registry.txt
      echo "TOKENS 15" ;;
    *) echo "TOKENS 5" ;;
  esac
  echo "TEXT follow-up done"
  exit 0
fi

if [ "$kind" = activation ]; then
  # What the work tree was seeded with, for the per-query fixture test.
  [ -n "$state" ] && printf '%s\t%s\n' "$(ls "$wd" | LC_ALL=C sort | paste -sd, -)" "$prompt" >> "$state/seeded"
  # Routing: load each installed skill whose description contains a 5+ letter
  # word from the request.
  fired=0
  if [ -n "$bundle" ]; then
    for f in "$bundle"/skills/*/SKILL.md; do
      [ -f "$f" ] || continue
      sname="$(basename "$(dirname "$f")")"
      desc="$(sed -n 's/^description: *//p' "$f" | tr 'A-Z' 'a-z')"
      for w in $(printf '%s\n' "$prompt" | tr 'A-Z' 'a-z' | tr -c 'a-z\n' ' '); do
        [ "${#w}" -ge 5 ] || continue
        case "$desc" in
          *"$w"*)
            echo "SKILL $sname"
            fired=1
            break ;;
        esac
      done
    done
  fi
  if [ "$fired" -eq 1 ]; then
    if [ "$mode" = linger ]; then sleep 30; fi
    exit 0
  fi
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
  case "$p" in *widget*) loaded=1; echo "SKILL $skill_name" ;; esac
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
  *"Write a skill"*)
    # With the skill loaded it names the plain requests too; without, only
    # the procedure. A misnamed skill fails validation before any triggering.
    desc="Use when renaming a widget."
    [ "$loaded" = 1 ] && desc="Use when renaming a widget or a gadget."
    name=gadget-helper
    [ "$mode" = skill-misnamed ] && name=gadget-helpers
    echo "TOOL Write"
    mkdir -p .agents/skills/gadget-helper
    printf -- '---\nname: %s\ndescription: "%s"\n---\n# Gadget helper\n' "$name" "$desc" > .agents/skills/gadget-helper/SKILL.md
    echo "TOKENS 50" ;;
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
