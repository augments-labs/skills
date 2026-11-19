#!/usr/bin/env bash
# bin/triggering with the fake adapter: splits, validity, the description
# hash, candidates, manual-only skills, early stop, and exit codes.
. "$(dirname "${BASH_SOURCE[0]}")/testlib.bash"

repo="$(tl_make_repo repo)" || tl_done
tl_use_fake "$repo"
TR="$TL_EVALS/bin/triggering"
SK=(--pack engineering --skill demo-skill --harness fake)
n=0
trig() { # args...; sets $ws, $rec, and $rc
  n=$((n + 1)); ws="$TL_TMP/ws/trig-$n"; rc=0
  "$TR" "${SK[@]}" --out "$ws" "$@" > "$TL_TMP/trig.out" 2> "$TL_TMP/trig.err" || rc=$?
  rec="$ws/triggering.json"
}
mode() { printf '%s\n' "$1" > "$FAKE_STATE/mode"; }
qres() { # $1 query text $2 jq field
  jq -c --arg q "$1" ".[] | select(.query == \$q) | $2" "$ws/query-results.json"
}
sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
committed_desc="Use when renaming a widget in the demo app."

# --- dry run and arguments ----------------------------------------------------
EVALS_COST_PER_SESSION=0.1 "$TR" "${SK[@]}" --dry-run > /dev/null 2> "$TL_TMP/dry.err"
eq "a dry run exits 0" 0 $?
eq "a dry run launches nothing" 0 "$(tl_launches)"
contains "the plan counts sessions" "$TL_TMP/dry.err" "6 queries x 3 run(s) = 18 agent session(s)"
contains "the plan lists splits" "$TL_TMP/dry.err" "holdout: 1 query"
contains "the plan is priced" "$TL_TMP/dry.err" "estimated cost: 1.80"
eq "a dry run writes no workspace" "" "$(ls -A "$EVALS_WORKSPACE")"
bad() { # $1 description $2 exit code, rest: args
  local d="$1" want="$2" got=0; shift 2
  "$TR" "${SK[@]}" "$@" > /dev/null 2>&1 || got=$?
  eq "$d exits $want" "$want" "$got"
}
bad "a threshold of 1.5" 2 --threshold 1.5 --dry-run
bad "a zero --runs" 2 --runs 0 --dry-run
bad "an unknown option" 2 --bogus
bad "an unknown harness" 2 --harness nope --dry-run
FAKE_RUNNABLE=no bad "a runnable=no adapter" 2 --runs 1
FAKE_CLI_MISSING=1 bad "a missing CLI" 3 --runs 1
printf 'Has a "quote"\n' > "$TL_TMP/bad-desc.txt"
bad "a candidate with a forbidden character" 2 --description-file "$TL_TMP/bad-desc.txt" --dry-run
eq "argument errors launch nothing" 0 "$(tl_launches)"

# --- the committed description ------------------------------------------------
trig --runs 2 --jobs 2
eq "a failing query exits 1" 1 "$rc"
eq "it prints the record path" "$rec" "$(cat "$TL_TMP/trig.out")"
eq "6 queries x 2 runs were launched" 12 "$(tl_launches)"
jeq "triggering.json has exactly the record keys" "$rec" 'keys' \
  '["harness","harness_version","manual_only","model","pack","plugin","runs","schema_version","skill","splits","threshold"]'
jeq "record header" "$rec" '[.schema_version, .pack, .skill, .manual_only, .harness, .harness_version, .model, .runs, .threshold]' \
  '[1,"engineering","demo-skill",false,"fake","fake 1.0","fake-model-1",2,0.5]'
jeq "plugin binds the commit and the skill tree" "$rec" '.plugin | [.commit, .skill_tree]' \
  "[\"$(git -C "$repo" rev-parse HEAD)\",\"$(git -C "$repo" rev-parse HEAD:skills/in-progress/demo-skill)\"]"
jeq "description_sha256 is the sha256 of the description value" "$rec" '.plugin.description_sha256' "\"$(sha "$committed_desc")\""
jeq "splits" "$rec" '.splits | keys' '["holdout","train","validation"]'
jeq "train split" "$rec" '.splits.train' '{"queries":3,"passed":2,"pass_rate":0.6667,"inconclusive":0}'
jeq "validation split" "$rec" '.splits.validation' '{"queries":2,"passed":1,"pass_rate":0.5,"inconclusive":0}'
jeq "holdout split" "$rec" '.splits.holdout' '{"queries":1,"passed":0,"pass_rate":0,"inconclusive":0}'
eq "a should-trigger query that loads passes" '["pass",1]' "$(qres "Rename the widget called oldWidget" '[.verdict, .rate]' | jq -c 'walk(if type == "number" then . + 0 else . end)')"
eq "a should-trigger query that never loads fails" '"fail"' "$(qres "Rename the gadget called oldGadget" .verdict)"
eq "a should-not query that stays quiet passes" '"pass"' "$(qres "What time is it in Tokyo" .verdict)"
contains "the summary prints verdicts" "$TL_TMP/trig.err" "(0/2)  [train] Rename the gadget called oldGadget"
contains "the summary pads verdicts" "$TL_TMP/trig.err" "  FAIL         + rate="
contains "the summary prints split rates" "$TL_TMP/trig.err" "train: 2/3 passed"
jeq "a run result" "$ws/q0/run-1/result.json" '[.valid, .triggered, .skill_chain, .reason]' '[true,true,["demo-skill"],null]'
eq "every session is an activation" 12 "$(grep -c '^launch kind=activation ' "$FAKE_LAUNCH_LOG")"
eq "every session gets the bundle" 0 "$(grep -c 'bundle=-' "$FAKE_LAUNCH_LOG")"
eq "the run directories are removed" "" "$(ls -A "$TMPDIR")"
lacks "the bundle carries no hooks" <(cd "$ws/bundle" && find . -type f) "hooks"

trig --runs 1 --splits train --json
jeq "--splits limits the record" "$TL_TMP/trig.out" '.splits | keys' '["train"]'

# --- a candidate description is scored but never bound ------------------------
cand="Use when renaming a widget or a gadget in the demo app."
printf '%s\n' "$cand" > "$TL_TMP/cand.txt"
trig --runs 1 --description-file "$TL_TMP/cand.txt"
eq "a candidate that routes every query exits 0" 0 "$rc"
jeq "a candidate has a null skill_tree" "$rec" '.plugin.skill_tree' null
jeq "a candidate's hash is its own" "$rec" '.plugin.description_sha256' "\"$(sha "$cand")\""
jeq "every split passes" "$rec" '[.splits[].pass_rate]' '[1,1,1]'
contains "the bundle carries the candidate" "$ws/bundle/skills/demo-skill/SKILL.md" "description: \"$cand\""
contains "the committed skill is untouched" "$repo/skills/in-progress/demo-skill/SKILL.md" "description: \"$committed_desc\""
lacks "a candidate run is not offered for recording" "$TL_TMP/trig.err" "record it with"

# --- invalid runs are inconclusive, never counted ----------------------------
inconc() { # $1 mode $2 reason, rest: args
  local m="$1" why="$2"; shift 2
  mode "$m"
  trig --runs 2 --splits train "$@"
  eq "$m: inconclusive exits 1" 1 "$rc"
  jeq "$m: no valid run, no rate" "$rec" '.splits.train' '{"queries":3,"passed":0,"pass_rate":null,"inconclusive":3}'
  jeq "$m: the run says why ($why)" "$ws/q2/run-1/result.json" '[.valid, .reason]' "[false,\"$why\"]"
}
inconc refuse refusal
contains "the summary prints INCONCLUSIVE" "$TL_TMP/trig.err" "INCONCLUSIVE + rate=- (0/0)"
inconc dead no_model_turn
inconc sleep timeout --timeout 1
mode ""
FAKE_INSTALL_FAIL=1 trig --runs 1 --splits train
jeq "an install failure is an invalid run" "$ws/q0/run-1/result.json" '[.valid, .reason]' '[false,"install_failed"]'

# --- early stop: the session ends once the skill loads ------------------------
if command -v pgrep > /dev/null 2>&1; then
  mode linger
  SECONDS=0
  trig --runs 1 --splits train --timeout 25
  took=$SECONDS
  check "a lingering session is stopped once the skill loads (${took}s)" test "$took" -lt 15
  jeq "the stopped run still counts as a trigger" "$ws/q0/run-1/result.json" '[.valid, .triggered]' '[true,true]'
  mode ""
else
  ok "# skip early stop: pgrep is not available"
fi

# --- manual-only skills -------------------------------------------------------
skf="$repo/skills/in-progress/demo-skill/SKILL.md"
qf="$repo/evals/engineering/demo-skill/queries.json"
awk 'NR == 2 { print "disable-model-invocation: true" } { print }' "$skf" > "$skf.tmp" && mv "$skf.tmp" "$skf"
( cd "$repo" && tl_git commit -qam "manual-only" ) || not_ok "commit manual-only"
bad "a manual-only skill with train queries" 2 --runs 1 --dry-run
jq '.queries = [.queries[0] | .split = "negative"]' "$qf" > "$qf.tmp" && mv "$qf.tmp" "$qf"
bad "a negative query that should trigger" 2 --runs 1 --dry-run
printf '%s\n' '{"queries": [{"query": "What time is it in Tokyo", "should_trigger": false, "split": "negative"},
  {"query": "Write a haiku about rain", "should_trigger": false, "split": "negative"}]}' > "$qf"
( cd "$repo" && tl_git commit -qam "negative queries" ) || not_ok "commit negative queries"
trig --runs 1
eq "a quiet manual-only skill exits 0" 0 "$rc"
jeq "a manual-only record" "$rec" '[.manual_only, (.splits | keys), .splits.negative.pass_rate]' '[true,["negative"],1]'

tl_done
