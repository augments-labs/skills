#!/usr/bin/env bash
# bin/report: merging compact benchmark/triggering summaries into
# evals/results/<pack>/<skill>.json and keeping the README scoreboard in sync.
. "$(dirname "${BASH_SOURCE[0]}")/testlib.bash"

RP="$TL_EVALS/bin/report"

# --- the real README ----------------------------------------------------------
( unset EVALS_REPO_ROOT; "$RP" --scoreboard --check ) > "$TL_TMP/real.out" 2>&1
eq "the repository README scoreboard is current" 0 $?

# --- a fixture repository -----------------------------------------------------
repo="$(tl_make_repo repo)" || tl_done
tl_use_fake "$repo"
readme="$repo/README.md"
results="$repo/evals/results"
SK=(--pack engineering --skill demo-skill --harness fake)

bench_ws() { # $1 name, rest: args; runs evaluate, prints the workspace
  local ws="$TL_TMP/ws/$1"; shift
  "$TL_EVALS/bin/evaluate" "${SK[@]}" --runs 1 --out "$ws" "$@" > /dev/null 2>&1
  printf '%s\n' "$ws"
}
trig_ws() { # $1 name, rest: args; runs triggering, prints the workspace
  local ws="$TL_TMP/ws/$1"; shift
  "$TL_EVALS/bin/triggering" "${SK[@]}" --runs 1 --out "$ws" "$@" > /dev/null 2>&1
  printf '%s\n' "$ws"
}
report() { rc=0; "$RP" "$@" > "$TL_TMP/report.out" 2> "$TL_TMP/report.err" || rc=$?; }

cp "$readme" "$TL_TMP/README.orig"
report --scoreboard
eq "--scoreboard with no records exits 0" 0 "$rc"
check "--scoreboard with no records leaves the README byte-identical" cmp -s "$readme" "$TL_TMP/README.orig"
contains "an empty results dir keeps the placeholder row" "$readme" "| *(No evaluated skills yet)* | n/a | n/a | n/a | n/a | n/a |"
report --scoreboard --check
eq "--check passes with no records" 0 "$rc"
report --scoreboard --bogus
eq "--scoreboard refuses an unknown option" 2 "$rc"
report
eq "no argument is a usage error" 2 "$rc"

# --- recording a benchmark ----------------------------------------------------
ws1="$(bench_ws eval-1)"
check "the evaluate run produced a record" test -f "$ws1/benchmark.json"
report "$ws1" --date 2026-01-02
eq "recording exits 0" 0 "$rc"
target="$results/engineering/demo-skill.json"
eq "it prints the compact record path" "$target" "$(cat "$TL_TMP/report.out")"
check "the compact per-skill record exists" test -f "$target"
jeq "the record stores skill metadata and one model entry" "$target" \
  '[.pack, .skill, (.results | length), .results[0].model, .results[0].harness, .results[0].date, .results[0].benchmark.shipped_arm, .results[0].benchmark.pass_rate, .results[0].benchmark.none_pass_rate, .results[0].benchmark.controls_passed]' \
  '["engineering","demo-skill",1,"fake-model-1","fake","2026-01-02","full",1,0,true]'
row='| `engineering/demo-skill` | fake-model-1 100% vs 0% | pass | n/a | 2026-01-02 | [demo-skill.json](evals/results/engineering/demo-skill.json) |'
contains "the scoreboard row is rendered" "$readme" "$row"
lacks "the placeholder row is replaced" "$readme" "No evaluated skills yet"
contains "text after the scoreboard is kept" "$readme" "Text after the scoreboard stays untouched."
eq "the block holds header, rule, and one row" 3 "$(awk '/eval-scoreboard:start/ { f = 1; next } /eval-scoreboard:end/ { f = 0 } f' "$readme" | wc -l | tr -d ' ')"
report --scoreboard --check
eq "--check passes after recording" 0 "$rc"

# Drift: a hand-edited row fails --check until --scoreboard rewrites it.
sed 's/100% vs 0%/90% vs 0%/' "$readme" > "$readme.tmp" && mv "$readme.tmp" "$readme"
report --scoreboard --check
eq "a drifted scoreboard fails --check" 1 "$rc"
contains "the drift is explained" "$TL_TMP/report.err" "scoreboard drift"
report --scoreboard
report --scoreboard --check
eq "--scoreboard repairs the drift" 0 "$rc"
contains "the repaired row" "$readme" "$row"

# --- merging a second model and triggering into the same file -----------------
mkdir -p "$TL_TMP/mod/other-model"
jq '.model = "other-model-2" | .run_summary.full.pass_rate = 0.5' "$ws1/benchmark.json" > "$TL_TMP/mod/other-model/benchmark.json"
report "$TL_TMP/mod/other-model" --date 2026-01-03
eq "a second model merges into the same skill file" 0 "$rc"
jeq "both models live in one file" "$target" '[.results[].model]' '["fake-model-1","other-model-2"]'
eq "still one row per skill in README" 1 "$(grep -c '^| `engineering/demo-skill`' "$readme")"
contains "both models appear in the scoreboard row" "$readme" "fake-model-1 100% vs 0% · other-model-2 50% vs 0%"

wt="$(trig_ws trig-1)"
report "$wt" --date 2026-01-04
eq "recording triggering exits 0" 0 "$rc"
jeq "triggering merges into the matching model entry" "$target" \
  '[.results[0].triggering.passed, .results[0].triggering.queries, .results[0].triggering.all_passed, (.description_sha256 | length)]' \
  '[3,6,false,64]'
contains "triggering ratio appears in the scoreboard" "$readme" "| 3/6 | 2026-01-04 |"

# Recording a new skill_tree replaces stale entries in place.
printf '\nA change.\n' >> "$repo/skills/in-progress/demo-skill/SKILL.md"
( cd "$repo" && tl_git commit -qam "v2 skill" ) || not_ok "commit v2 skill"
ws2="$(bench_ws eval-2 --arms full,none)"
report "$ws2" --date 2026-01-05
eq "recording a new skill tree exits 0" 0 "$rc"
jeq "a new skill tree replaces previous entries" "$target" \
  '[(.results | length), .results[0].date, (.results[0] | has("triggering")), has("description_sha256")]' \
  '[1,"2026-01-05",false,false]'

# --- records that are refused -------------------------------------------------
refused() { # $1 description $2 expected error fragment, rest: report args
  local d="$1" frag="$2"; shift 2
  cp "$target" "$TL_TMP/target.before"
  report "$@"
  if [ "$rc" -ne 0 ] && grep -qF -- "$frag" "$TL_TMP/report.err"; then ok "refuses $d"; else not_ok "refuses $d (rc=$rc: $(cat "$TL_TMP/report.err"))"; fi
  check "refusing $d leaves existing record untouched" cmp -s "$TL_TMP/target.before" "$target"
}
mk() { # $1 name $2 jq filter; a modified copy of ws2
  mkdir -p "$TL_TMP/mod/$1"; jq "$2" "$ws2/benchmark.json" > "$TL_TMP/mod/$1/benchmark.json"
}
mk hooks '.hooks_enabled = true'
refused "a record with hooks enabled" "hooks_enabled must be false" "$TL_TMP/mod/hooks" --date 2026-02-01
mk unmeasured '.shipped_arm = "old_skill"'
refused "an unmeasured shipped_arm" "shipped_arm was not measured" "$TL_TMP/mod/unmeasured" --date 2026-02-01
mk schema '.schema_version = 2'
refused "another schema version" "schema_version must be 1" "$TL_TMP/mod/schema" --date 2026-02-01
mk name '.skill = "Demo Skill"'
refused "a non-kebab skill" "'skill' must be kebab-case" "$TL_TMP/mod/name" --date 2026-02-01
refused "a bad date" "bad date" "$ws2" --date 2026-1-2
mkdir -p "$TL_TMP/mod/empty"
refused "a directory with no record" "exactly one of" "$TL_TMP/mod/empty"
mkdir -p "$TL_TMP/mod/both"
cp "$ws2/benchmark.json" "$TL_TMP/mod/both/"
printf '{}\n' > "$TL_TMP/mod/both/triggering.json"
refused "a directory with both records" "exactly one of" "$TL_TMP/mod/both"
printf '{}\n' > "$TL_TMP/mod/other.json"
refused "a file that is not a record" "a record is benchmark.json or triggering.json" "$TL_TMP/mod/other.json"

printf '\nAn uncommitted line.\n' >> "$repo/skills/in-progress/demo-skill/SKILL.md"
ws3="$(bench_ws eval-dirty --eval change-greeting --arms full)"
refused "a benchmark of an uncommitted skill" "skill_tree is null" "$ws3" --date 2026-02-01
git -C "$repo" checkout -q -- skills/in-progress/demo-skill/SKILL.md

printf 'Use when renaming a widget or a gadget.\n' > "$TL_TMP/cand.txt"
wc_="$(trig_ws trig-candidate --description-file "$TL_TMP/cand.txt")"
refused "a candidate description" "plugin.skill_tree or plugin.description_sha256 is null" "$wc_" --date 2026-02-01
mkdir -p "$TL_TMP/mod/nosplits"
jq '.splits = {}' "$wt/triggering.json" > "$TL_TMP/mod/nosplits/triggering.json"
refused "a triggering record with no splits" "triggering record has no splits" "$TL_TMP/mod/nosplits" --date 2026-02-01

eq "evals/results holds only per-skill json files" "$results/engineering/demo-skill.json" "$(find "$results" -type f)"
report --scoreboard --check
eq "the scoreboard is current at the end" 0 "$rc"

tl_done
