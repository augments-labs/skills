#!/usr/bin/env bash
# bin/report: recording benchmark.json / triggering.json into evals/results/
# and keeping the README scoreboard in sync.
. "$(dirname "${BASH_SOURCE[0]}")/testlib.bash"

RP="$TL_EVALS/bin/report"

# --- the real README ----------------------------------------------------------
( unset EVALS_REPO_ROOT; "$RP" --scoreboard --check ) > "$TL_TMP/real.out" 2>&1
eq "the repository README scoreboard is current" 0 $?
contains "an empty results dir keeps the pending row" "$TL_ROOT/README.md" "| *(Pending first evaluated promotion for \`v0.0.1\`)* | n/a | n/a | n/a | n/a | n/a | n/a |"

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
report --scoreboard --check
eq "--check passes with no records" 0 "$rc"
report --scoreboard --bogus
eq "--scoreboard refuses an unknown option" 2 "$rc"
report
eq "no argument is a usage error" 2 "$rc"

# --- recording a benchmark ----------------------------------------------------
ws1="$(bench_ws eval-1)"
check "the evaluate run produced a record" test -f "$ws1/benchmark.json"
measured="$(jq -r '.measured_at[0:10]' "$ws1/benchmark.json")"
report "$ws1" --date 2026-01-02
eq "recording exits 0" 0 "$rc"
target="$results/2026-01-02-engineering-demo-skill-fake"
eq "it prints the record path" "$target/benchmark.json" "$(cat "$TL_TMP/report.out")"
eq "the results dir holds only the record" "benchmark.json" "$(ls -A "$target")"
check "the record is copied verbatim" cmp -s "$ws1/benchmark.json" "$target/benchmark.json"
row="| \`engineering/demo-skill\` | \`distilled\` | 100% vs 0% | +0 calls / +0 calls, +0 turns | +0 output (small fix) | fake-model-1, $measured | [2026-01-02-engineering-demo-skill-fake](evals/results/2026-01-02-engineering-demo-skill-fake/benchmark.json) |"
contains "the scoreboard row is rendered" "$readme" "$row"
lacks "the pending row is replaced" "$readme" "Pending first evaluated promotion"
contains "the header is kept" "$readme" "| Skill | Arm shipped | Pass rate (\`shipped\` vs \`none\`) | Control delta (non-trigger / small fix) | Token delta | Model & date | Record |"
contains "text after the scoreboard is kept" "$readme" "Text after the scoreboard stays untouched."
eq "the block holds header, rule, and one row" 3 "$(awk '/eval-scoreboard:start/ { f = 1; next } /eval-scoreboard:end/ { f = 0 } f' "$readme" | wc -l | tr -d ' ')"
report --scoreboard --check
eq "--check passes after recording" 0 "$rc"

report "$ws1" --date 2026-01-02
eq "an existing target is refused" 1 "$rc"
contains "the refusal says records are immutable" "$TL_TMP/report.err" "already recorded"

# Drift: a hand-edited row fails --check until --scoreboard rewrites it.
sed 's/100% vs 0%/90% vs 0%/' "$readme" > "$readme.tmp" && mv "$readme.tmp" "$readme"
report --scoreboard --check
eq "a drifted scoreboard fails --check" 1 "$rc"
contains "the drift is explained" "$TL_TMP/report.err" "scoreboard drift"
report --scoreboard
report --scoreboard --check
eq "--scoreboard repairs the drift" 0 "$rc"
contains "the repaired row" "$readme" "$row"

# The latest record per skill wins.
ws2="$(bench_ws eval-2 --shipped-arm full)"
report "$ws2" --date 2026-01-03
eq "a second record exits 0" 0 "$rc"
eq "one row per skill" 1 "$(grep -c '^| `engineering/demo-skill`' "$readme")"
contains "the latest record is shown" "$readme" "| \`engineering/demo-skill\` | \`full\` | 100% vs 0% |"
contains "it links the latest record" "$readme" "(evals/results/2026-01-03-engineering-demo-skill-fake/benchmark.json)"

# --- records that are refused -------------------------------------------------
refused() { # $1 description $2 expected error fragment, rest: report args
  local d="$1" frag="$2"; shift 2
  local before; before="$(ls "$results" 2>/dev/null | wc -l)"
  report "$@"
  if [ "$rc" -ne 0 ] && grep -qF -- "$frag" "$TL_TMP/report.err"; then ok "refuses $d"; else not_ok "refuses $d (rc=$rc: $(cat "$TL_TMP/report.err"))"; fi
  eq "refusing $d writes nothing" "$before" "$(ls "$results" 2>/dev/null | wc -l)"
}
mk() { # $1 name $2 jq filter; a modified copy of the first record
  mkdir -p "$TL_TMP/mod/$1"; jq "$2" "$ws1/benchmark.json" > "$TL_TMP/mod/$1/benchmark.json"
}
mk hooks '.hooks_enabled = true'
refused "a record with hooks enabled" "hooks_enabled must be false" "$TL_TMP/mod/hooks" --date 2026-02-01
mk unmeasured '.shipped_arm = "old_skill"'
refused "an unmeasured shipped_arm" "shipped_arm was not measured" "$TL_TMP/mod/unmeasured" --date 2026-02-01
mk schema '.schema_version = 2'
refused "another schema version" "schema_version must be 1" "$TL_TMP/mod/schema" --date 2026-02-01
mk name '.skill = "Demo Skill"'
refused "a non-kebab skill" "'skill' must be kebab-case" "$TL_TMP/mod/name" --date 2026-02-01
refused "a bad date" "bad date" "$ws1" --date 2026-1-2
mkdir -p "$TL_TMP/mod/empty"
refused "a directory with no record" "exactly one of" "$TL_TMP/mod/empty"
mkdir -p "$TL_TMP/mod/both"
cp "$ws1/benchmark.json" "$TL_TMP/mod/both/"
printf '{}\n' > "$TL_TMP/mod/both/triggering.json"
refused "a directory with both records" "exactly one of" "$TL_TMP/mod/both"
printf '{}\n' > "$TL_TMP/mod/other.json"
refused "a file that is not a record" "a record is benchmark.json or triggering.json" "$TL_TMP/mod/other.json"

printf '\nAn uncommitted line.\n' >> "$repo/skills/in-progress/demo-skill/SKILL.md"
ws3="$(bench_ws eval-dirty --eval change-greeting --arms full)"
refused "a benchmark of an uncommitted skill" "skill_tree is null" "$ws3" --date 2026-02-01
git -C "$repo" checkout -q -- skills/in-progress/demo-skill/SKILL.md

# --- recording triggering -----------------------------------------------------
cp "$readme" "$TL_TMP/README.before-trig"
wt="$(trig_ws trig-1)"
report "$wt" --date 2026-01-04
eq "recording triggering exits 0" 0 "$rc"
eq "a triggering record gets the -triggering suffix" "triggering.json" "$(ls -A "$results/2026-01-04-engineering-demo-skill-fake-triggering")"
check "a triggering record leaves the scoreboard alone" cmp -s "$readme" "$TL_TMP/README.before-trig"
printf 'Use when renaming a widget or a gadget.\n' > "$TL_TMP/cand.txt"
wc_="$(trig_ws trig-candidate --description-file "$TL_TMP/cand.txt")"
refused "a candidate description" "plugin.skill_tree or plugin.description_sha256 is null" "$wc_" --date 2026-02-01
wtr="$(trig_ws trig-train --splits train)"
refused "a triggering record with no validation split" "needs a validation split" "$wtr" --date 2026-02-01

eq "evals/results holds records only" "" "$(find "$results" -type f ! -name benchmark.json ! -name triggering.json)"
report --scoreboard --check
eq "the scoreboard is current at the end" 0 "$rc"

tl_done
