#!/usr/bin/env bash
# Case validation and deterministic grading (bin/grade, evalkit cases/grade).
. "$(dirname "${BASH_SOURCE[0]}")/testlib.bash"
. "$TL_EVALS/lib/common.sh"

ek() { python3 -I "$TL_EVALS/lib/evalkit.py" "$@"; }

# --- case validation ----------------------------------------------------------
cdir="$TL_TMP/cases"
mkdir -p "$cdir/files/app"
printf 'print("ok")\n' > "$cdir/verify.py"
reject() { # $1 description $2 evals.json body $3 expected error fragment
  printf '%s\n' "$2" > "$cdir/evals.json"
  local out
  if out="$(ek cases "$cdir/evals.json" 2>&1)"; then
    not_ok "rejects $1 (accepted)"
  elif printf '%s' "$out" | grep -qF -- "$3"; then
    ok "rejects $1"
  else
    not_ok "rejects $1 (error was: $out)"
  fi
}
A='{"type":"file-exists","path":"a.txt"}'
reject "pending_first_run" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":['"$A"'],"pending_first_run":true}]}' "pending_first_run"
reject "an empty case list" '{"evals":[]}' "non-empty 'evals'"
reject "a non-kebab id" '{"evals":[{"id":"Bad_Id","kind":"trap","prompt":"p","assertions":['"$A"']}]}' "kebab-case"
reject "a duplicate id" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":['"$A"']},{"id":"a","kind":"trap","prompt":"p","assertions":['"$A"']}]}' "duplicate id"
reject "an unknown kind" '{"evals":[{"id":"a","kind":"capability","prompt":"p","assertions":['"$A"']}]}' "'kind' must be one of"
reject "an empty prompt" '{"evals":[{"id":"a","kind":"trap","prompt":" ","assertions":['"$A"']}]}' "non-empty 'prompt'"
reject "a trap with no assertion" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[]}]}' "at least one assertion"
reject "allowed_files outside non_trigger" '{"evals":[{"id":"a","kind":"small_fix","prompt":"p","allowed_files":["x"],"assertions":['"$A"']}]}' "non_trigger cases only"
reject "an unknown assertion type" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"llm-judge"}]}]}' "unknown assertion type"
reject "a path that escapes" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"file-exists","path":"../x"}]}]}' "stay inside"
reject "an absolute path" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"file-exists","path":"/etc/passwd"}]}]}' "stay inside"
reject "an invalid regex" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"file-contains","path":"a","pattern":"("}]}]}' "invalid regex"
reject "a git-count with no bound" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"git-count","count":"commits"}]}]}' "'min' and/or 'max'"
reject "a git-count of something else" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"git-count","count":"lines","max":1}]}]}' "'commits' or 'changed_files'"
reject "a script with source and path" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"script","source":"x","path":"verify.py"}]}]}' "exactly one of"
reject "a missing verifier" '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"script","path":"nope.py"}]}]}' "verifier not found"
reject "a missing fixture" '{"evals":[{"id":"a","kind":"trap","prompt":"p","fixture":"gone","assertions":['"$A"']}]}' "fixture directory not found"
reject "follow-ups that are not a list" '{"evals":[{"id":"a","kind":"trap","prompt":"p","followups":"next","assertions":['"$A"']}]}' "'followups' must be a non-empty list"
reject "an empty follow-up list" '{"evals":[{"id":"a","kind":"trap","prompt":"p","followups":[],"assertions":['"$A"']}]}' "'followups' must be a non-empty list"
reject "a null follow-up list" '{"evals":[{"id":"a","kind":"trap","prompt":"p","followups":null,"assertions":['"$A"']}]}' "'followups' must be a non-empty list"
reject "an empty follow-up" '{"evals":[{"id":"a","kind":"trap","prompt":"p","followups":["next",""],"assertions":['"$A"']}]}' "followups[1]: a follow-up must be a non-empty string"
reject "a blank follow-up" '{"evals":[{"id":"a","kind":"trap","prompt":"p","followups":["  "],"assertions":['"$A"']}]}' "followups[0]: a follow-up must be a non-empty string"
reject "a follow-up that is not a string" '{"evals":[{"id":"a","kind":"trap","prompt":"p","followups":[1],"assertions":['"$A"']}]}' "followups[0]: a follow-up must be a non-empty string"
printf '%s\n' '{"queries":[{"query":"a","should_trigger":true},{"query":"b","should_trigger":false}]}' > "$cdir/q.json"
printf '%s\n' '{"queries":[]}' > "$cdir/q-empty.json"
st() { printf '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":[{"type":"skill-triggering",%s}]}]}' "$1"; }
reject "a skill-triggering with no path" "$(st '"queries":"q.json"')" "path must be a non-empty string"
reject "a skill-triggering path that escapes" "$(st '"path":"../x","queries":"q.json"')" "stay inside"
reject "a skill-triggering with no queries" "$(st '"path":".agents/skills/*"')" "path must be a non-empty string"
reject "a missing skill-triggering queries file" "$(st '"path":".agents/skills/*","queries":"nope.json"')" "queries file not found: nope.json"
reject "an invalid skill-triggering queries file" "$(st '"path":".agents/skills/*","queries":"q-empty.json"')" "q-empty.json: queries.json needs a non-empty 'queries' array"
reject "a zero skill-triggering runs" "$(st '"path":".agents/skills/*","queries":"q.json","runs":0')" "'runs' must be a positive integer"
reject "a skill-triggering threshold of 1" "$(st '"path":".agents/skills/*","queries":"q.json","threshold":1')" "'threshold' must be between 0 and 1"
printf '%s\n' "$(st '"path":".agents/skills/*","queries":"q.json","runs":2')" > "$cdir/evals.json"
check "accepts a skill-triggering assertion" q ek cases "$cdir/evals.json"
jeq "trigger-plan counts queries x runs per assertion" <(ek trigger-plan "$cdir" - < <(ek cases "$cdir/evals.json")) \
  '[.[] | [.case, .index, .path, .runs, .threshold, .sessions]]' '[["a",0,".agents/skills/*",2,0.5,4]]'
eq "trigger-plan resolves the queries file in the case dir" "$cdir/q.json" "$(ek cases "$cdir/evals.json" | ek trigger-plan "$cdir" - | jq -r '.[0].queries')"
eq "trigger-plan is empty for a case without one" "[]" "$(printf '%s' '{"id":"b","assertions":[{"type":"file-exists","path":"x"}]}' | ek trigger-plan "$cdir" - | jq -c .)"
printf '%s\n' '{"evals":[{"id":"a","kind":"trap","prompt":"p","assertions":['"$A"']}]}' > "$cdir/evals.json"
refute "rejects an unknown --only id" q ek cases "$cdir/evals.json" --only zzz

fx="$TL_FIX/repo/evals/engineering/demo-skill/evals.json"
check "accepts the fixture cases" q ek cases "$fx"
eq "keeps evals.json order" "rename-widget,fix-readme-typo,change-greeting" "$(ek cases "$fx" | jq -r 'map(.id) | join(",")')"
eq "filters with --only" "change-greeting" "$(ek cases "$fx" --only change-greeting | jq -r 'map(.id) | join(",")')"
eq "a case without follow-ups has no followups key" "false,false,false" "$(ek cases "$fx" | jq -r 'map(has("followups")) | join(",")')"
printf '%s\n' '{"evals":[{"id":"a","kind":"trap","prompt":"p","followups":["Now the registry.","Thanks."],"assertions":['"$A"']}]}' > "$cdir/evals.json"
eq "follow-ups pass through in order, after the prompt" '["id","kind","prompt","followups","fixture","allowed_files","assertions"]|["Now the registry.","Thanks."]' \
  "$(ek cases "$cdir/evals.json" | jq -c '.[0] | (keys_unsorted | tostring) + "|" + (.followups | tostring)' | jq -r .)"
eq "every kind and assertion type is covered by the fixture" \
  "change-greeting,fix-readme-typo,rename-widget|command-succeeds,file-contains,file-exists,file-not-contains,git-count,script|non_trigger,small_fix,trap" \
  "$(jq -r '[(.evals | map(.id) | sort | join(",")), ([.evals[].assertions[].type] | unique | join(",")), ([.evals[].kind] | unique | join(","))] | join("|")' "$fx")"

# --- grading ------------------------------------------------------------------
wd="$TL_TMP/grade/work"
rd="$TL_TMP/grade/run"
mkdir -p "$rd"
seed_workdir "$wd" "$TL_FIX/repo/evals/engineering/demo-skill/files/app" || not_ok "seed the grading work tree"
check "seed_workdir tags the seed commit" q git -C "$wd" rev-parse -q --verify seed
printf 'const newWidget = "Hi";\n' > "$wd/src/app.js"
printf 'newWidget\n' > "$wd/registry.txt"
printf 'notes\n' > "$wd/NOTES.md"
lab_changed_files "$wd" seed > "$rd/changed-files.txt"
eq "changed files include untracked and modified paths" "NOTES.md,registry.txt,src/app.js" "$(paste -sd, "$rd/changed-files.txt")"
jq -n --arg wd "$wd" '{outcome: "completed", workdir: $wd}' > "$rd/run_status.json"

grade_one() { # $1 assertion json [$2 kind] [$3 allowed json]; prints the assertion status
  jq -n --argjson a "$1" --arg k "${2:-trap}" --argjson al "${3:-[]}" \
    '{id: "x", kind: $k, prompt: "p", allowed_files: $al, assertions: [$a]}' > "$rd/case.json"
  "$TL_EVALS/bin/grade" "$rd" "$rd/case.json" "$cdir" > /dev/null 2>&1 || { echo error; return; }
  jq -r '.assertion_results[0].status // .summary.outcome' "$rd/grading.json"
}
eq "file-exists passes"            pass "$(grade_one '{"type":"file-exists","path":"src/app.js"}')"
eq "file-exists fails"             fail "$(grade_one '{"type":"file-exists","path":"src/missing.js"}')"
eq "file-contains passes"          pass "$(grade_one '{"type":"file-contains","path":"src/app.js","pattern":"\\bnewWidget\\b"}')"
eq "file-contains fails"           fail "$(grade_one '{"type":"file-contains","path":"src/app.js","pattern":"oldWidget"}')"
eq "file-contains honors ignore_case" pass "$(grade_one '{"type":"file-contains","path":"src/app.js","pattern":"NEWWIDGET","ignore_case":true}')"
eq "file-contains is multiline"    pass "$(grade_one '{"type":"file-contains","path":"registry.txt","pattern":"^newWidget$"}')"
eq "file-not-contains passes"      pass "$(grade_one '{"type":"file-not-contains","path":"src/app.js","pattern":"Hello"}')"
eq "file-not-contains fails"       fail "$(grade_one '{"type":"file-not-contains","path":"src/app.js","pattern":"Hi"}')"
eq "command-succeeds passes"       pass "$(grade_one '{"type":"command-succeeds","command":"grep -qx newWidget registry.txt"}')"
eq "command-succeeds fails"        fail "$(grade_one '{"type":"command-succeeds","command":"exit 3"}')"
eq "a command timeout needs review" needs_review "$(grade_one '{"type":"command-succeeds","command":"sleep 5","timeout":1}')"
eq "git-count changed_files passes" pass "$(grade_one '{"type":"git-count","count":"changed_files","min":3,"max":3}')"
eq "git-count changed_files fails"  fail "$(grade_one '{"type":"git-count","count":"changed_files","max":1}')"
eq "git-count commits passes"       pass "$(grade_one '{"type":"git-count","count":"commits","max":0}')"
eq "git-count commits fails"        fail "$(grade_one '{"type":"git-count","count":"commits","min":1}')"
eq "script source passes"          pass "$(grade_one '{"type":"script","source":"import sys, pathlib; sys.exit(0 if pathlib.Path(sys.argv[1], \"registry.txt\").read_text().strip() == \"newWidget\" else 1)"}')"
eq "script source fails"           fail "$(grade_one '{"type":"script","source":"import sys; sys.exit(1)"}')"
eq "a crashing script needs review" needs_review "$(grade_one '{"type":"script","source":"raise SystemExit(2)"}')"
eq "script path passes"            pass "$(grade_one '{"type":"script","path":"verify.py"}')"
ln -s /etc "$wd/escape"
eq "a symlink out of the tree fails" fail "$(grade_one '{"type":"file-exists","path":"escape/hostname"}')"
rm "$wd/escape"

# Verifiers run agent-written code: no operator environment, a scratch HOME.
export EVALS_TEST_SECRET=operator-secret
eq "verifiers get a scrubbed environment" pass \
  "$(grade_one '{"type":"command-succeeds","command":"[ -z \"${EVALS_TEST_SECRET:-}\" ] && [ -n \"$EVAL_WORKDIR\" ] && [ -f \"$EVAL_CHANGED_FILES\" ] && [ \"$EVAL_SEED\" = seed ]"}')"
eq "verifiers get a scratch HOME" pass \
  "$(grade_one "$(jq -nc --arg h "$HOME" '{type: "command-succeeds", command: ("[ \"$HOME\" != \"" + $h + "\" ] && [ -d \"$HOME\" ]")}')")"
unset EVALS_TEST_SECRET

# Unrequested files: only non_trigger cases, matched against allowed_files globs.
grade_one '{"type":"file-exists","path":"README.md"}' non_trigger '["src/*.js","registry.txt"]' > /dev/null
jeq "non_trigger flags files outside allowed_files" "$rd/grading.json" '.controls.unrequested_files' '["NOTES.md"]'
grade_one '{"type":"file-exists","path":"README.md"}' non_trigger '["*"]' > /dev/null
jeq "a matching glob allows every file" "$rd/grading.json" '.controls.unrequested_files' '[]'
grade_one '{"type":"file-exists","path":"README.md"}' trap > /dev/null
jeq "trap cases never count unrequested files" "$rd/grading.json" '.controls.unrequested_files' '[]'

# skill-triggering grades what evaluate saved in <run>/triggering-<i>/.
ST='{"type":"skill-triggering","path":".agents/skills/*","queries":"q.json"}'
td="$rd/triggering-0"
qrow() { jq -nc --argjson t "$1" --arg v "$2" '{should_trigger: $t, verdict: $v}'; }
results() { mkdir -p "$td"; jq -s . > "$td/query-results.json"; }
detail_one() { jq -r '.assertion_results[0].detail' "$rd/grading.json"; }
rm -rf "$td"
eq "skill-triggering with nothing saved needs review" needs_review "$(grade_one "$ST")"
{ qrow true pass; qrow true pass; qrow false pass; } | results
eq "skill-triggering passes when every query passes" pass "$(grade_one "$ST")"
eq "skill-triggering details both sides" "should-trigger 2/2, should-not 1/1" "$(detail_one)"
{ qrow true pass; qrow true fail; qrow false pass; } | results
eq "a missed should-trigger query fails" fail "$(grade_one "$ST")"
eq "the detail counts the miss" "should-trigger 1/2, should-not 1/1" "$(detail_one)"
{ qrow true pass; qrow false fail; } | results
eq "a should-not query that loads fails" fail "$(grade_one "$ST")"
{ qrow true pass; qrow true inconclusive; qrow false fail; } | results
eq "an inconclusive query needs review" needs_review "$(grade_one "$ST")"
eq "the detail counts inconclusive queries" "should-trigger 1/2, should-not 0/1, 1 inconclusive" "$(detail_one)"
printf 'expected one skill at .agents/skills/*/SKILL.md, found 0\n' > "$td/invalid.txt"
eq "no written skill fails" fail "$(grade_one "$ST")"
eq "the detail says why" "expected one skill at .agents/skills/*/SKILL.md, found 0" "$(detail_one)"
rm -f "$td/invalid.txt"; printf 'evals/bin/triggering exited 2\n' > "$td/error.txt"
eq "a triggering error needs review" needs_review "$(grade_one "$ST")"
rm -rf "$td"
jq -n --argjson a "$ST" '{id: "x", kind: "trap", prompt: "p", assertions: [{type: "file-exists", path: "README.md"}, $a]}' > "$rd/case.json"
mkdir -p "$rd/triggering-1"; qrow true pass | jq -s . > "$rd/triggering-1/query-results.json"
"$TL_EVALS/bin/grade" "$rd" "$rd/case.json" "$cdir" > /dev/null 2>&1
jeq "each assertion reads its own triggering-<index>" "$rd/grading.json" '[.assertion_results[].status]' '["pass","pass"]'
rm -rf "$rd/triggering-1"

# written-skill: the one valid skill a run wrote under a glob.
sw="$TL_TMP/written-work"
mkdir -p "$sw"
eq "no written skill is reported" "expected one skill at .agents/skills/*/SKILL.md, found 0" "$(ek written-skill "$sw" '.agents/skills/*')"
refute "no written skill exits 1" q ek written-skill "$sw" '.agents/skills/*'
mkdir -p "$sw/.agents/skills/gadget-helper"
printf -- '---\nname: gadget-helper\ndescription: "Use when renaming a gadget."\n---\n' > "$sw/.agents/skills/gadget-helper/SKILL.md"
eq "one valid skill prints its directory" "$(cd "$sw" && pwd -P)/.agents/skills/gadget-helper" "$(ek written-skill "$sw" '.agents/skills/*')"
mkdir -p "$sw/.agents/skills/other"
printf -- '---\nname: other\ndescription: "Use when."\n---\n' > "$sw/.agents/skills/other/SKILL.md"
eq "two written skills are reported" "expected one skill at .agents/skills/*/SKILL.md, found 2: .agents/skills/gadget-helper, .agents/skills/other" \
  "$(ek written-skill "$sw" '.agents/skills/*')"
rm -rf "$sw/.agents/skills/other"
sed -i 's/^name: .*/name: gadget-helpers/' "$sw/.agents/skills/gadget-helper/SKILL.md"
eq "a name that differs from its directory is reported" ".agents/skills/gadget-helper: name 'gadget-helpers' does not match its directory 'gadget-helper'" \
  "$(ek written-skill "$sw" '.agents/skills/*')"
sed -i 's/^name: .*/name: Gadget_Helper/' "$sw/.agents/skills/gadget-helper/SKILL.md"
eq "an invalid name is reported" ".agents/skills/gadget-helper: name 'Gadget_Helper' is not a valid skill name" "$(ek written-skill "$sw" '.agents/skills/*')"
printf -- '---\nname: gadget-helper\n---\n' > "$sw/.agents/skills/gadget-helper/SKILL.md"
eq "a skill with no description is reported" ".agents/skills/gadget-helper/SKILL.md: no description in frontmatter" "$(ek written-skill "$sw" '.agents/skills/*')"
printf 'no frontmatter\n' > "$sw/.agents/skills/gadget-helper/SKILL.md"
eq "a skill with no frontmatter is reported" ".agents/skills/gadget-helper/SKILL.md: missing YAML frontmatter" "$(ek written-skill "$sw" '.agents/skills/*')"
rm -rf "$sw/.agents"; mkdir -p "$sw/.agents/skills"
ln -s "$(cd "$sw" && pwd -P)/../written-elsewhere" "$sw/.agents/skills/escape"
mkdir -p "$TL_TMP/written-elsewhere"
printf -- '---\nname: escape\ndescription: "Use when."\n---\n' > "$TL_TMP/written-elsewhere/SKILL.md"
refute "a written skill outside the work tree is refused" q ek written-skill "$sw" '.agents/skills/*'

# Outcomes: any needs_review wins, then any fail.
jq -n '{id: "x", kind: "trap", prompt: "p", assertions: [
  {type: "file-exists", path: "src/app.js"}, {type: "file-exists", path: "nope"},
  {type: "script", source: "raise SystemExit(2)"}]}' > "$rd/case.json"
eq "bin/grade prints the outcome" needs_review "$("$TL_EVALS/bin/grade" "$rd" "$rd/case.json" "$cdir" 2>/dev/null)"
jeq "summary counts each status" "$rd/grading.json" '.summary | [.passed, .failed, .needs_review, .total]' '[1,1,1,3]'

# An indeterminate run is never graded.
jq -n --arg wd "$wd" '{outcome: "indeterminate", reason: "timeout", workdir: $wd}' > "$rd/run_status.json"
eq "an indeterminate run grades as indeterminate" indeterminate "$("$TL_EVALS/bin/grade" "$rd" "$rd/case.json" "$cdir" 2>/dev/null)"
jeq "an indeterminate run has no pass rate and no assertion results" "$rd/grading.json" '[.summary.pass_rate, (.assertion_results | length)]' '[null,0]'

tl_done
