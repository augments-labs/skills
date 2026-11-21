#!/usr/bin/env bash
# bin/evaluate end to end with the fake adapter and the scripted agent: arms,
# isolation, hooks OFF, denominator-safe controls, and the benchmark record.
. "$(dirname "${BASH_SOURCE[0]}")/testlib.bash"

repo="$(tl_make_repo repo)" || tl_done
tl_use_fake "$repo"
EV="$TL_EVALS/bin/evaluate"
SK=(--pack engineering --skill demo-skill --harness fake)
n=0
evaluate() { # args...; sets $ws and $rc
  n=$((n + 1)); ws="$TL_TMP/ws/run-$n"; rc=0
  "$EV" "${SK[@]}" --out "$ws" "$@" > "$TL_TMP/evaluate.out" 2> "$TL_TMP/evaluate.err" || rc=$?
  bench="$ws/benchmark.json"
}
mode() { printf '%s\n' "$1" > "$FAKE_STATE/mode"; }

# --- dry run ------------------------------------------------------------------
EVALS_COST_PER_SESSION=0.5 "$EV" "${SK[@]}" --dry-run > /dev/null 2> "$TL_TMP/dry.err"
eq "a dry run exits 0" 0 $?
eq "a dry run launches nothing" 0 "$(tl_launches)"
contains "the default plan is 3 cases x 3 arms x 3 runs" "$TL_TMP/dry.err" "3 case(s) x 3 arm(s) x 3 run(s) = 27 agent session(s), 1 at a time"
contains "the default worst-case wall time is serial" "$TL_TMP/dry.err" "worst-case wall time: 405 min at --timeout 900"
contains "the default arms are full,distilled,none" "$TL_TMP/dry.err" "arms=full,distilled,none"
contains "the plan states hooks are off" "$TL_TMP/dry.err" "hooks OFF in every arm"
contains "the plan is priced" "$TL_TMP/dry.err" "estimated cost: 13.50"
eq "a dry run writes no workspace" "" "$(ls -A "$EVALS_WORKSPACE")"
"$EV" "${SK[@]}" --jobs 3 --dry-run > /dev/null 2> "$TL_TMP/dry.err"
eq "a --jobs 3 dry run exits 0" 0 $?
contains "the --jobs 3 plan names concurrency" "$TL_TMP/dry.err" "27 agent session(s), 3 at a time"
contains "the --jobs 3 worst-case wall time divides by jobs" "$TL_TMP/dry.err" "worst-case wall time: 135 min at --timeout 900"
"$EV" "${SK[@]}" --jobs 4 --dry-run > /dev/null 2> "$TL_TMP/dry.err"
contains "the --jobs 4 worst-case wall time rounds up" "$TL_TMP/dry.err" "worst-case wall time: 105 min at --timeout 900"
FAKE_CLI_MISSING=1 FAKE_RUNNABLE=no "$EV" "${SK[@]}" --dry-run > /dev/null 2> "$TL_TMP/dry.err"
eq "a dry run needs no CLI and no runnable adapter" 0 $?
contains "a dry run names an unverified adapter" "$TL_TMP/dry.err" "runnable=no"

# --- argument errors ----------------------------------------------------------
bad() { # $1 description, rest: args
  local d="$1"; shift
  if "$EV" "${SK[@]}" --dry-run "$@" > /dev/null 2>&1; then not_ok "refuses $d"; else ok "refuses $d"; fi
}
bad "an unknown arm" --arms full,bogus
bad "arms without full" --arms distilled,none
bad "a repeated arm" --arms full,full
bad "old_skill without --base" --arms full,old_skill
bad "--base without old_skill" --base HEAD
bad "an unknown --base" --arms full,old_skill --base no-such-commit
bad "a zero --runs" --runs 0
bad "a zero --jobs" --jobs 0
bad "a negative --jobs" --jobs -1
bad "a non-numeric --jobs" --jobs abc
bad "a leading-zero --jobs" --jobs 01
bad "a bad --shipped-arm" --shipped-arm none
bad "--shipped-arm distilled without the arm" --arms full,none --shipped-arm distilled
bad "an unknown case id" --eval nope
bad "an unknown harness" --harness ../fake
eq "argument errors launch nothing" 0 "$(tl_launches)"

# --- adapter gates ------------------------------------------------------------
FAKE_RUNNABLE=no evaluate --runs 1 --eval change-greeting
eq "a runnable=no adapter exits 2" 2 "$rc"
contains "the refusal names --allow-unverified" "$TL_TMP/evaluate.err" "--allow-unverified"
eq "a runnable=no adapter launches nothing" 0 "$(tl_launches)"
FAKE_CLI_MISSING=1 evaluate --runs 1 --eval change-greeting
eq "a missing CLI exits 3" 3 "$rc"
FAKE_RUNNABLE=no evaluate --runs 1 --eval change-greeting --arms full --allow-unverified
eq "--allow-unverified runs an unverified adapter" 0 "$rc"
eq "--allow-unverified ran one session" 1 "$(tl_launches)"
: > "$FAKE_LAUNCH_LOG"; rm -f "$FAKE_STATE/launches"

# --- a full promotion run -----------------------------------------------------
mkdir -p "$EVALS_CREDENTIAL_SEED/fake"
printf 'FAKE_API_KEY=seeded-key\n' > "$EVALS_CREDENTIAL_SEED/fake/.eval-env"
printf 'token\n' > "$EVALS_CREDENTIAL_SEED/fake/.fake-token"
export EVALS_TEST_SECRET=operator-secret
evaluate --runs 1
unset EVALS_TEST_SECRET
eq "a promotion run exits 0" 0 "$rc"
eq "it prints the benchmark path" "$bench" "$(cat "$TL_TMP/evaluate.out")"
eq "it ran 3 cases x 3 arms x 1 run" 9 "$(tl_launches)"

jeq "benchmark.json has exactly the record keys" "$bench" 'keys' \
  '["arms","deltas","evals","harness","harness_version","hooks_enabled","measured_at","mode","model","pack","run_summary","runs_per_eval","schema_version","shipped_arm","skill"]'
jeq "record header" "$bench" '[.schema_version, .pack, .skill, .mode, .harness, .harness_version, .model, .runs_per_eval, .hooks_enabled]' \
  '[1,"engineering","demo-skill","promotion","fake","fake 1.0","fake-model-1",1,false]'
check "measured_at is a UTC timestamp" q jq -e '.measured_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")' "$bench"
head="$(git -C "$repo" rev-parse HEAD)"
jeq "arms bind the full skill tree" "$bench" '.arms.full' \
  "{\"commit\":\"$head\",\"skill_tree\":\"$(git -C "$repo" rev-parse HEAD:skills/in-progress/demo-skill)\"}"
jeq "arms bind the distilled tree" "$bench" '.arms.distilled' \
  "{\"commit\":\"$head\",\"skill_tree\":\"$(git -C "$repo" rev-parse HEAD:evals/engineering/demo-skill/distilled)\"}"
jeq "the none arm is null" "$bench" '.arms | has("none") and .none == null' true
jeq "run_summary has one entry per arm" "$bench" '.run_summary | keys' '["distilled","full","none"]'
jeq "an arm summary has exactly its keys" "$bench" '.run_summary.full | keys' \
  '["control_non_trigger","control_small_fix","indeterminate_count","mean_output_tokens","mean_time_seconds","needs_review_count","pass_rate","scored_runs"]'
jeq "control_non_trigger keys" "$bench" '.run_summary.full.control_non_trigger | keys' '["median_tool_calls","skill_loads","unrequested_files"]'
jeq "control_small_fix keys" "$bench" '.run_summary.full.control_small_fix | keys' '["median_output_tokens","median_tool_calls","median_turns","pass_rate"]'
jeq "trap pass rates: the skill teaches the registry step" "$bench" '[.run_summary.full.pass_rate, .run_summary.distilled.pass_rate, .run_summary.none.pass_rate]' '[1,1,0]'
jeq "pass_rate counts trap runs only" "$bench" '[.run_summary[].scored_runs]' '[1,1,1]'
jeq "no run was indeterminate" "$bench" '[.run_summary[].indeterminate_count]' '[0,0,0]'
jeq "non_trigger controls" "$bench" '.run_summary.distilled.control_non_trigger' '{"skill_loads":0,"unrequested_files":0,"median_tool_calls":1}'
jeq "small_fix controls use output tokens" "$bench" '.run_summary.full.control_small_fix' '{"pass_rate":1,"median_output_tokens":30,"median_tool_calls":1,"median_turns":1}'
jeq "deltas are fractions" "$bench" '.deltas' '{"full_vs_none":1,"distilled_vs_none":1,"full_vs_distilled":0}'
jeq "per-case arms" "$bench" '.evals[0]' '{"id":"rename-widget","kind":"trap","arms":{"full":{"scored_runs":1,"passed":1,"indeterminate":0,"needs_review":0},"distilled":{"scored_runs":1,"passed":1,"indeterminate":0,"needs_review":0},"none":{"scored_runs":1,"passed":0,"indeterminate":0,"needs_review":0}}}'
jeq "the decision table ships distilled" "$bench" '.shipped_arm' '"distilled"'
contains "the decision is explained" "$TL_TMP/evaluate.err" "decision: distilled beats none"

# Raw runs stay in the workspace; only the record would be copied to results/.
rd="$ws/runs/rename-widget/full/run-1"
for f in prompt.txt stream.ndjson stderr.log response.txt run_status.json metrics.json grading.json changed-files.txt diff.patch; do
  check "a run keeps $f" test -f "$rd/$f"
done
jeq "run_status records hooks off and the skill chain" "$rd/run_status.json" '[.outcome, .hooks_enabled, .skill_chain]' '["completed",false,["demo-skill"]]'
jeq "metrics" "$rd/metrics.json" '[.output_tokens, .tool_calls, .turns, .model]' '[120,3,1,"fake-model-1"]'
contains "a plain-text stream is kept as the answer text" "$rd/response.txt" "TEXT done"
contains "the diff is kept" "$rd/diff.patch" "+newWidget"

# Hooks stay OFF: bundles hold SKILL.md and its support dirs, never hooks/.
eq "the full bundle holds only skill files" "./skills/demo-skill/SKILL.md ./skills/demo-skill/references/guide.md" \
  "$(cd "$ws/bundles/full" && find . -type f | sort | paste -sd' ')"
eq "the distilled bundle holds only its SKILL.md" "./skills/demo-skill/SKILL.md" \
  "$(cd "$ws/bundles/distilled" && find . -type f | sort | paste -sd' ')"
check "the source skill does carry a hooks file" test -f "$repo/skills/in-progress/demo-skill/hooks/hooks.json"
lacks "no installed bundle carried hooks" "$FAKE_STATE/bundle.behavioral" "hooks"
eq "the none arm installs nothing" 3 "$(grep -c 'bundle=-' "$FAKE_LAUNCH_LOG")"

# Isolation: a fresh HOME per session, outside the repo, removed afterwards;
# credentials seeded; the operator environment cleared.
eq "every session had its own HOME" 9 "$(sed -n 's/.* home=\([^ ]*\) .*/\1/p' "$FAKE_STATE/launches" | sort -u | wc -l | tr -d ' ')"
bad_home=0
while read -r h; do
  case "$h" in "$TMPDIR"/augments-evals-*/home) ;; *) bad_home=1 ;; esac
  [ -e "$h" ] && bad_home=1
  [ "$h" = "$EVALS_OPERATOR_HOME" ] && bad_home=1
done < <(sed -n 's/.* home=\([^ ]*\) .*/\1/p' "$FAKE_STATE/launches")
eq "homes live under TMPDIR and are removed" 0 "$bad_home"
eq "the run directories are removed" "" "$(ls -A "$TMPDIR")"
eq "sessions run in their work tree" 9 "$(awk '{ split($3, a, "="); split($4, b, "="); if (a[2] == b[2]) n++ } END { print n + 0 }' "$FAKE_STATE/launches")"
eq "credentials and .eval-env are seeded into every session" 9 "$(grep -c 'api_key=seeded-key .*token_file=yes' "$FAKE_STATE/launches")"
eq "the operator environment never reaches a session" 0 "$(grep -c 'leaked=operator-secret' "$FAKE_STATE/launches")"
lacks "a session environment has no operator secret" "$FAKE_STATE/env.behavioral" "EVALS_TEST_SECRET"
contains "a session has no route to a session bus" "$FAKE_STATE/env.behavioral" "DBUS_SESSION_BUS_ADDRESS=unix:path="
refute "no credential lands in the workspace" q grep -rq seeded-key "$ws"
rm -rf "$EVALS_CREDENTIAL_SEED/fake"

# --- the shipped-arm flag -----------------------------------------------------
evaluate --runs 1 --shipped-arm full
jeq "--shipped-arm overrides the decision table" "$bench" '.shipped_arm' '"full"'

# --- control gates: a skill that sprawls is not shipped distilled -------------
mode sprawl
evaluate --runs 1
jeq "unrequested files are counted per arm" "$bench" '[.run_summary[].control_non_trigger.unrequested_files]' '[1,1,0]'
jeq "a failed control gate ships full" "$bench" '.shipped_arm' '"full"'
contains "the failed gate is named" "$TL_TMP/evaluate.err" "distilled control gate: non_trigger unrequested_files=1"
jeq "the sprawl did not change the trap pass rate" "$bench" '.run_summary.full.pass_rate' 1

# --- indeterminate runs are counted apart ------------------------------------
indet() { # $1 mode $2 expected reason, rest: extra args
  local m="$1" want="$2"; shift 2
  mode "$m"
  evaluate --runs 2 --eval rename-widget --arms full,none "$@"
  eq "$m: evaluate still exits 0" 0 "$rc"
  jeq "$m: runs are indeterminate ($want)" "$ws/runs/rename-widget/full/run-1/run_status.json" '[.outcome, .reason]' "[\"indeterminate\",\"$want\"]"
  jeq "$m: indeterminate runs are not scored" "$bench" '.run_summary.full | [.pass_rate, .scored_runs, .indeterminate_count]' '[null,0,2]'
  jeq "$m: per-case counts" "$bench" '.evals[0].arms.full' '{"scored_runs":0,"passed":0,"indeterminate":2,"needs_review":0}'
}
indet dead no_model_turn
indet refuse refusal
indet crash nonzero_exit
indet sleep timeout --timeout 1

mode none-loads
evaluate --runs 1 --eval rename-widget --arms full,none
jeq "a skill loaded in the none arm is indeterminate" "$ws/runs/rename-widget/none/run-1/run_status.json" '.reason' '"skill_loaded_in_none"'
jeq "the full arm is still scored" "$bench" '[.run_summary.full.pass_rate, .run_summary.none.indeterminate_count, .run_summary.none.pass_rate]' '[1,1,null]'
jeq "no delta without a scored none run" "$bench" '.deltas.full_vs_none' null

mode ""
FAKE_INSTALL_FAIL=1 evaluate --runs 1 --eval rename-widget --arms full
jeq "an install failure is indeterminate" "$ws/runs/rename-widget/full/run-1/run_status.json" '.reason' '"install_failed"'
mkdir -p "$TL_TMP/seed-file"
printf 'x\n' > "$TL_TMP/seed-file/fake"
EVALS_CREDENTIAL_SEED="$TL_TMP/seed-file" evaluate --runs 1 --eval rename-widget --arms full
eq "a credential seed that is not a directory is skipped" completed "$(jq -r .outcome "$ws/runs/rename-widget/full/run-1/run_status.json")"

# --- parallel runs (--jobs) ---------------------------------------------------
: > "$FAKE_LAUNCH_LOG"; rm -rf "$FAKE_STATE/launches" "$FAKE_STATE/concurrency" "$FAKE_STATE/active"
mode parallel
evaluate --runs 2 --eval change-greeting --arms full,distilled,none --jobs 3
eq "--jobs 3 parallel run exits 0" 0 "$rc"
eq "--jobs 3 ran all 6 sessions" 6 "$(tl_launches)"
max_conc="$(awk 'BEGIN { m = 0 } $1 + 0 > m { m = $1 + 0 } END { print m }' "$FAKE_STATE/concurrency")"
check "--jobs 3 ran sessions concurrently (peak=${max_conc})" test "$max_conc" -ge 2
check "--jobs 3 never exceeded the concurrency cap (peak=${max_conc})" test "$max_conc" -le 3
eq "--jobs 3 gave every session its own HOME" 6 "$(sed -n 's/.* home=\([^ ]*\) .*/\1/p' "$FAKE_STATE/launches" | sort -u | wc -l | tr -d ' ')"
eq "--jobs 3 removed all run directories" "" "$(ls -A "$TMPDIR")"
contains "--jobs 3 completion logs name the run" "$TL_TMP/evaluate.err" "done: change-greeting [small_fix] arm=full run=1 -> pass"
jeq "--jobs 3 scored all 6 small_fix runs" "$bench" '[.run_summary.full.control_small_fix.pass_rate, .run_summary.distilled.control_small_fix.pass_rate, .run_summary.none.control_small_fix.pass_rate]' '[1,1,1]'
jeq "--jobs 3 had zero indeterminate runs" "$bench" '[.run_summary[].indeterminate_count]' '[0,0,0]'

: > "$FAKE_LAUNCH_LOG"; rm -rf "$FAKE_STATE/launches" "$FAKE_STATE/concurrency" "$FAKE_STATE/active"
mode ""
evaluate --runs 1 --jobs 3
eq "a parallel promotion run exits 0" 0 "$rc"
eq "a parallel promotion run launched all 9 sessions" 9 "$(tl_launches)"
jeq "parallel promotion trap pass rates match serial" "$bench" '[.run_summary.full.pass_rate, .run_summary.distilled.pass_rate, .run_summary.none.pass_rate]' '[1,1,0]'
jeq "parallel promotion deltas match serial" "$bench" '.deltas' '{"full_vs_none":1,"distilled_vs_none":1,"full_vs_distilled":0}'
jeq "parallel promotion ships distilled" "$bench" '.shipped_arm' '"distilled"'
eq "parallel promotion removed all run directories" "" "$(ls -A "$TMPDIR")"

# Signal cleanup: SIGTERM stops active parallel workers and removes homes/run dirs.
: > "$FAKE_LAUNCH_LOG"; rm -rf "$FAKE_STATE/launches"
mode sleep
n=$((n + 1)); ws_sig="$TL_TMP/ws/run-$n"
"$EV" "${SK[@]}" --out "$ws_sig" --runs 1 --eval rename-widget --arms full,distilled,none --jobs 3 --timeout 30 \
  > "$TL_TMP/sig.out" 2> "$TL_TMP/sig.err" &
ev_pid=$!
waited=0
while [ "$(tl_launches)" -lt 3 ] && [ "$waited" -lt 100 ]; do
  sleep 0.1
  waited=$((waited + 1))
done
eq "SIGTERM test saw all 3 parallel workers launch" 3 "$(tl_launches)"
SECONDS=0
kill -TERM "$ev_pid" 2>/dev/null || true
sig_rc=0
wait "$ev_pid" 2>/dev/null || sig_rc=$?
sig_took=$SECONDS
check "SIGTERM exits nonzero (rc=${sig_rc})" test "$sig_rc" -ne 0
check "SIGTERM stopped workers promptly (${sig_took}s)" test "$sig_took" -lt 10
eq "SIGTERM removed every isolated home and run dir" "" "$(ls -A "$TMPDIR")"
mode ""

# --- interleaved launch order (run -> arm -> case) ----------------------------
: > "$FAKE_LAUNCH_LOG"; rm -rf "$FAKE_STATE/launches"
evaluate --runs 2 --arms full,none
eq "interleaved run exits 0" 0 "$rc"
first_three="$(awk -F'/' '{ print $(NF-3) "/" $(NF-2) "/" $(NF-1) }' <(sed -n 's/.* wd=\([^ ]*\) .*/\1/p' "$FAKE_STATE/launches" | head -n 3) | paste -sd' ')"
eq "launches interleave cases before repeating a case" \
  "rename-widget/full/run-1 fix-readme-typo/full/run-1 change-greeting/full/run-1" "$first_three"

# --- resume (--resume) --------------------------------------------------------
resume_eval() { # args...; sets $rc
  rc=0
  "$EV" "$@" > "$TL_TMP/resume.out" 2> "$TL_TMP/resume.err" || rc=$?
}
bad_resume() {
  local d="$1"; shift
  if "$EV" "$@" > /dev/null 2>&1; then not_ok "refuses $d"; else ok "refuses $d"; fi
}
bad_resume "--resume combined with --pack" --resume "$ws_sig" --pack engineering
bad_resume "--resume combined with --runs" --resume "$ws_sig" --runs 1
bad_resume "--resume on a missing dir" --resume "$TL_TMP/no-such-ws"
mkdir -p "$TL_TMP/empty-ws"
bad_resume "--resume on a dir without plan.json" --resume "$TL_TMP/empty-ws"

# Resume the SIGTERM-interrupted workspace: all 3 interrupted slots run and score.
: > "$FAKE_LAUNCH_LOG"; rm -rf "$FAKE_STATE/launches"
EVALS_COST_PER_SESSION=0.5 resume_eval --resume "$ws_sig" --jobs 2 --dry-run
eq "--resume --dry-run exits 0" 0 "$rc"
eq "--resume --dry-run launches nothing" 0 "$(tl_launches)"
contains "--resume --dry-run reports missing slots" "$TL_TMP/resume.err" "3 of 3 session(s) to run (0 complete, 3 missing, 0 refusal), 2 at a time"
contains "--resume --dry-run prices only pending sessions" "$TL_TMP/resume.err" "estimated cost: 1.50"
resume_eval --resume "$ws_sig" --jobs 2
eq "--resume after SIGTERM exits 0" 0 "$rc"
eq "--resume after SIGTERM prints benchmark path" "$ws_sig/benchmark.json" "$(cat "$TL_TMP/resume.out")"
eq "--resume after SIGTERM ran the 3 interrupted sessions" 3 "$(tl_launches)"
jeq "--resume after SIGTERM produces valid trap pass rates" "$ws_sig/benchmark.json" \
  '[.run_summary.full.pass_rate, .run_summary.distilled.pass_rate, .run_summary.none.pass_rate]' '[1,1,0]'
eq "--resume after SIGTERM removed all run directories" "" "$(ls -A "$TMPDIR")"

# Resume after refusal: re-runs refusal slots only, leaving completed slots untouched.
mode refuse
evaluate --runs 1 --eval rename-widget,fix-readme-typo --arms full,none
ws_ref="$ws"
jeq "refusal run records indeterminate counts" "$ws_ref/benchmark.json" '[.run_summary.full.indeterminate_count, .run_summary.none.indeterminate_count]' '[2,2]'
: > "$FAKE_LAUNCH_LOG"; rm -rf "$FAKE_STATE/launches"
mode ""
resume_eval --resume "$ws_ref" --dry-run
contains "--resume --dry-run counts refusal slots" "$TL_TMP/resume.err" "4 of 4 session(s) to run (0 complete, 0 missing, 4 refusal)"
resume_eval --resume "$ws_ref" --jobs 2
eq "--resume after refusal exits 0" 0 "$rc"
eq "--resume after refusal re-ran all 4 refusal sessions" 4 "$(tl_launches)"
jeq "--resume after refusal clears indeterminate counts" "$ws_ref/benchmark.json" '[.run_summary.full.indeterminate_count, .run_summary.none.indeterminate_count]' '[0,0]'
jeq "--resume after refusal scores traps properly" "$ws_ref/benchmark.json" '[.run_summary.full.pass_rate, .run_summary.none.pass_rate]' '[1,0]'

# Resume never cherry-picks: completed pass/fail and non-refusal timeout runs are skipped.
mode sleep
evaluate --runs 1 --eval rename-widget --arms full,none --timeout 1
ws_to="$ws"
: > "$FAKE_LAUNCH_LOG"; rm -rf "$FAKE_STATE/launches"
mode ""
resume_eval --resume "$ws_to" --dry-run
contains "--resume treats timeout as complete (not retried)" "$TL_TMP/resume.err" "0 of 2 session(s) to run (2 complete, 0 missing, 0 refusal)"
resume_eval --resume "$ws_to"
eq "--resume with 0 pending exits 0" 0 "$rc"
eq "--resume with 0 pending launches nothing" 0 "$(tl_launches)"
jeq "--resume preserves timeout indeterminate counts" "$ws_to/benchmark.json" '[.run_summary.full.indeterminate_count, .run_summary.none.indeterminate_count]' '[1,1]'

# Partial workspace: keeps completed pass/fail untouched, re-runs only missing & corrupt slots.
evaluate --runs 2 --eval rename-widget --arms full,none
ws_part="$ws"
printf 'keep\n' > "$ws_part/runs/rename-widget/full/run-1/sentinel.txt"
printf 'keep\n' > "$ws_part/runs/rename-widget/none/run-1/sentinel.txt"
rm -rf "$ws_part/runs/rename-widget/full/run-2"
printf '{broken' > "$ws_part/runs/rename-widget/none/run-2/grading.json"
: > "$FAKE_LAUNCH_LOG"; rm -rf "$FAKE_STATE/launches"
resume_eval --resume "$ws_part" --jobs 2
eq "--resume partial workspace exits 0" 0 "$rc"
eq "--resume partial workspace ran only the 2 incomplete slots" 2 "$(tl_launches)"
check "--resume preserved completed passing slot" test -f "$ws_part/runs/rename-widget/full/run-1/sentinel.txt"
check "--resume preserved completed failing slot" test -f "$ws_part/runs/rename-widget/none/run-1/sentinel.txt"
jeq "--resume partial workspace restored full counts" "$ws_part/benchmark.json" '[.run_summary.full.scored_runs, .run_summary.full.pass_rate, .run_summary.none.scored_runs, .run_summary.none.pass_rate]' '[2,1,2,0]'

# Refuses to resume when the committed skill tree has changed.
: > "$FAKE_LAUNCH_LOG"
printf '\nChanged after initial run.\n' >> "$repo/skills/in-progress/demo-skill/SKILL.md"
resume_eval --resume "$ws_part"
check "--resume refuses a modified skill tree" test "$rc" -ne 0
contains "--resume explains the skill tree mismatch" "$TL_TMP/resume.err" "skill tree changed"
eq "--resume mismatch launches nothing" 0 "$(tl_launches)"
git -C "$repo" checkout -q -- skills/in-progress/demo-skill/SKILL.md

# --- edit mode: full vs the skill at --base ----------------------------------
erepo="$(tl_make_repo edit-repo)" || tl_done
tl_use_fake "$erepo"
skf="$erepo/skills/in-progress/demo-skill/SKILL.md"
cp "$skf" "$TL_TMP/SKILL.v2"
grep -v registry "$TL_TMP/SKILL.v2" > "$skf"
( cd "$erepo" && tl_git commit -qam "v1: no registry step" ) || not_ok "commit v1"
v1="$(git -C "$erepo" rev-parse HEAD)"
cp "$TL_TMP/SKILL.v2" "$skf"
( cd "$erepo" && tl_git commit -qam "v2: registry step" ) || not_ok "commit v2"
evaluate --runs 1 --arms full,old_skill --base "$v1"
eq "an edit run exits 0" 0 "$rc"
jeq "edit mode" "$bench" '[.mode, .shipped_arm]' '["edit","full"]'
jeq "old_skill binds the base commit's tree" "$bench" '.arms.old_skill' \
  "{\"commit\":\"$v1\",\"skill_tree\":\"$(git -C "$erepo" rev-parse "$v1:skills/in-progress/demo-skill")\"}"
jeq "the edit is measured against the old skill" "$bench" '[.run_summary.full.pass_rate, .run_summary.old_skill.pass_rate, .deltas.full_vs_old_skill]' '[1,0,1]'
jeq "edit deltas" "$bench" '.deltas | keys' '["full_vs_old_skill"]'
lacks "the old bundle is built from the base commit" "$ws/bundles/old_skill/skills/demo-skill/SKILL.md" "registry"
check "the old bundle carries no hooks" test ! -e "$ws/bundles/old_skill/skills/demo-skill/hooks"

# --- an uncommitted skill is never bound to a tree ---------------------------
printf '\nAn uncommitted line.\n' >> "$skf"
evaluate --runs 1 --eval change-greeting --arms full
jeq "a dirty skill records a null skill_tree" "$bench" '.arms.full.skill_tree' null
contains "the null tree is explained" "$TL_TMP/evaluate.err" "uncommitted changes"

tl_done
