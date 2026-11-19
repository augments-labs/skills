#!/usr/bin/env bash
# bin/optimize-description with the fake adapter: the score/revise loop, the
# reviser seeing train failures only, selection by validation, the holdout
# scored once, --apply, and the refusals.
. "$(dirname "${BASH_SOURCE[0]}")/testlib.bash"

repo="$(tl_make_repo repo)" || tl_done
tl_use_fake "$repo"
OPT="$TL_EVALS/bin/optimize-description"
SK=(--pack engineering --skill demo-skill --harness fake)
skf="$repo/skills/in-progress/demo-skill/SKILL.md"
committed='description: "Use when renaming a widget in the demo app."'
revised="Use when renaming a widget in the demo app. Covers requests like: Rename the gadget called oldGadget."
n=0
opt() { # args...; sets $ws, $rec, and $rc
  n=$((n + 1)); ws="$TL_TMP/ws/opt-$n"; rc=0
  "$OPT" "${SK[@]}" --out "$ws" "$@" > "$TL_TMP/opt.out" 2> "$TL_TMP/opt.err" || rc=$?
  rec="$ws/optimization.json"
}
bad() { # $1 description $2 exit code, rest: args
  local d="$1" want="$2" got=0; shift 2
  "$OPT" "${SK[@]}" "$@" > /dev/null 2>&1 || got=$?
  eq "$d exits $want" "$want" "$got"
}

# --- dry run and arguments ----------------------------------------------------
EVALS_COST_PER_SESSION=0.1 "$OPT" "${SK[@]}" --dry-run > /dev/null 2> "$TL_TMP/dry.err"
eq "a dry run exits 0" 0 $?
eq "a dry run launches nothing" 0 "$(tl_launches)"
contains "the plan counts scoring sessions" "$TL_TMP/dry.err" "at most 5 round(s) x 5 train+validation queries x 3 run(s) = 75 scoring session(s)"
contains "the plan counts reviser and holdout sessions" "$TL_TMP/dry.err" "+ up to 4 reviser session(s) + 3 holdout session(s) for the winner"
contains "the plan is priced" "$TL_TMP/dry.err" "estimated cost: at most 8.20"
eq "a dry run writes no workspace" "" "$(ls -A "$EVALS_WORKSPACE")"
bad "a zero --max-iterations" 2 --max-iterations 0 --dry-run
bad "an unknown option" 2 --bogus
bad "a missing --skill" 2 --pack engineering --skill "" --dry-run
bad "an unknown skill" 2 --skill nope --dry-run
FAKE_RUNNABLE=no bad "a runnable=no adapter" 2 --runs 1
FAKE_CLI_MISSING=1 bad "a missing CLI" 3 --runs 1
eq "argument errors launch nothing" 0 "$(tl_launches)"

# --- the loop -----------------------------------------------------------------
opt --runs 1 --jobs 2
eq "a selected iteration exits 0" 0 "$rc"
eq "it prints the record path" "$rec" "$(cat "$TL_TMP/opt.out")"
jeq "optimization.json keys" "$rec" 'keys' \
  '["applied","best_description","best_iteration","harness","holdout","iterations","max_iterations","measured_at","outcome","pack","runs","schema_version","skill","stop_reason"]'
jeq "the loop stops once train has no failure" "$rec" '[.outcome, .stop_reason, (.iterations | length)]' '["selected","train has no failure",2]'
jeq "iteration 1 scores the committed description" "$rec" '.iterations[0] | [.description, .train.pass_rate, .validation.pass_rate]' \
  '["Use when renaming a widget in the demo app.",0.6667,0.5]'
jeq "iteration 2 scores the revision" "$rec" '.iterations[1] | [.description, .train.pass_rate, .validation.pass_rate]' \
  "[\"$revised\",1,1]"
jeq "validation selects iteration 2" "$rec" '[.best_iteration, .best_description]' "[2,\"$revised\"]"
jeq "the holdout is scored once, for the winner" "$rec" '.holdout' '{"queries":1,"passed":1,"pass_rate":1,"inconclusive":0}'
jeq "nothing is applied without --apply" "$rec" '.applied' false
contains "the committed skill is untouched" "$skf" "$committed"
eq "5 + 5 scoring sessions, 1 holdout session" 11 "$(grep -c '^launch kind=activation ' "$FAKE_LAUNCH_LOG")"
eq "one reviser session" 1 "$(grep -c '^launch kind=behavioral ' "$FAKE_LAUNCH_LOG")"
check "the reviser runs with no skill installed" grep -q '^launch kind=behavioral .* bundle=-$' "$FAKE_LAUNCH_LOG"
jeq "rounds score train and validation only" "$ws/iteration-1/triggering/triggering.json" '.splits | keys' '["train","validation"]'
jeq "the holdout round scores the holdout only" "$ws/holdout/triggering.json" '.splits | keys' '["holdout"]'
check "the winner's description is kept" test "$(cat "$ws/iteration-2/description.txt")" = "$revised"
eq "the run directories are removed" "" "$(ls -A "$TMPDIR")"

rp="$ws/iteration-1/reviser-prompt.txt"
contains "the reviser sees the current description" "$rp" "Use when renaming a widget in the demo app."
contains "the reviser sees the skill body" "$rp" "keep \`registry.txt\`"
contains "the reviser sees the train failure" "$rp" "- should load the skill, but did not: Rename the gadget called oldGadget"
lacks "the reviser never sees a passing train query" "$rp" "Rename the widget called oldWidget"
lacks "the reviser never sees validation queries" "$rp" "The gadget label is wrong"
lacks "the reviser never sees validation negatives" "$rp" "Write a haiku about rain"
lacks "the reviser never sees the holdout" "$rp" "Swap the gadget title"
lacks "the reviser never sees the frontmatter" "$rp" "name: demo-skill"

# --- selection keeps the committed description when it is best ---------------
opt --runs 1 --max-iterations 1 --apply
eq "a single round exits 0" 0 "$rc"
jeq "the cap stops the loop" "$rec" '[.stop_reason, .best_iteration, .applied]' '["reached --max-iterations 1",1,false]'
check "no reviser runs on the last round" test ! -e "$ws/iteration-1/reviser-prompt.txt"
contains "applying the committed description writes nothing" "$TL_TMP/opt.err" "nothing to write"
jeq "the committed description fails the holdout" "$rec" '.holdout.pass_rate' 0
contains "the skill is unchanged" "$skf" "$committed"

# --- --apply ------------------------------------------------------------------
opt --runs 1 --apply
eq "--apply exits 0" 0 "$rc"
jeq "--apply is recorded" "$rec" '.applied' true
contains "--apply writes the winner into SKILL.md" "$skf" "description: \"$revised\""
contains "--apply keeps the skill name" "$skf" "name: demo-skill"
contains "--apply keeps the body" "$skf" "A synthetic skill for the offline eval suites."
contains "the operator is told to record a fresh run" "$TL_TMP/opt.err" "record a fresh evals/bin/triggering run"
git -C "$repo" checkout -q -- skills/in-progress/demo-skill/SKILL.md

# --- nothing to select --------------------------------------------------------
printf 'dead\n' > "$FAKE_STATE/mode"
opt --runs 1 --apply
eq "an all-inconclusive round exits 2" 2 "$rc"
jeq "nothing is selected" "$rec" '[.outcome, .best_iteration, .best_description, .applied]' '["indeterminate",null,null,false]'
contains "the stop reason says why" "$rec" "train scored nothing"
contains "the skill is not touched" "$skf" "$committed"
printf '\n' > "$FAKE_STATE/mode"

mkdir -p "$TL_TMP/ws/exists"
bad "an existing workspace" 2 --runs 1 --out "$TL_TMP/ws/exists"

# --- manual-only skills -------------------------------------------------------
awk 'NR == 2 { print "disable-model-invocation: true" } { print }' "$skf" > "$skf.tmp" && mv "$skf.tmp" "$skf"
bad "a manual-only skill" 2 --runs 1 --dry-run
contains "the refusal names the reason" <("$OPT" "${SK[@]}" --dry-run 2>&1) "manual-only"

tl_done
