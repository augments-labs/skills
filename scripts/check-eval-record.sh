#!/usr/bin/env bash
# Monorepo eval-record, anti-gaming, and self-attestation gate for augments-labs/skills.
# Enforces that any PR promoting or editing a skill under skills/<pack>/<name>/
# (excluding skills/in-progress/ and skills/deprecated/) names committed eval
# records under <evals_dir>/results/, blocks editing <evals_dir>/<pack>/<name>/**
# in the same PR without --allow-assertion-edit, and blocks self-attestation when
# both skills/ and the eval-record gate itself change in one PR.
set -euo pipefail
export LC_ALL=C

base=""
head_rev=""
evals_dir="evals"
body_file=""
exempt=0
allow_assertion_edit=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --head) head_rev="$2"; shift 2 ;;
    --evals) evals_dir="${2%/}"; shift 2 ;;
    --body) body_file="$2"; shift 2 ;;
    --exempt) exempt=1; shift ;;
    --allow-assertion-edit) allow_assertion_edit=1; shift ;;
    --help|-h)
      echo "Usage: bash scripts/check-eval-record.sh --base REV --head REV --evals DIR --body FILE [--exempt] [--allow-assertion-edit]"
      exit 0
      ;;
    *)
      echo "check-eval-record.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

[ -n "$base" ] && [ -n "$head_rev" ] && [ -n "$body_file" ] && [ -f "$body_file" ] || {
  echo "check-eval-record.sh: --base, --head, and readable --body are required" >&2
  exit 2
}

mb=$(git merge-base "$base" "$head_rev")
changed=$(git diff --name-only "$mb" "$head_rev")

# Find promoted skills touched in SKILL.md, references/, or assets/.
touched_skills=$(printf '%s\n' "$changed" | awk -F'/' '
  $1 == "skills" && $2 != "in-progress" && $2 != "deprecated" && NF >= 4 {
    if ($4 == "SKILL.md" || $4 == "references" || $4 == "assets") {
      print $2 "/" $3
    }
  }
' | sort -u)

if [ -z "$touched_skills" ]; then
  echo "ok: no promoted skills modified; no eval record required."
  exit 0
fi

# Self-attestation guard: a PR changing the eval-record gate cannot attest its own skill change.
if printf '%s\n' "$changed" | grep -qE '^(scripts/check-eval-record\.sh|\.github/workflows/eval-record\.yml)$'; then
  echo "FAIL: PR modifies both promoted skills and the eval-record gate (self-attestation forbidden; split into two PRs)." >&2
  exit 1
fi

# Anti-gaming check: modifying <evals_dir>/<pack>/<name>/** in the same PR as skills/<pack>/<name>/.
if [ "$allow_assertion_edit" -ne 1 ]; then
  while IFS= read -r sk; do
    [ -n "$sk" ] || continue
    if printf '%s\n' "$changed" | grep -qE "^${evals_dir}/${sk}/"; then
      echo "FAIL: PR modifies both skills/${sk}/ and ${evals_dir}/${sk}/ without maintainer label 'eval-assertion-reviewed'." >&2
      exit 1
    fi
  done <<< "$touched_skills"
fi

if [ "$exempt" -eq 1 ]; then
  echo "ok: --exempt (no-eval label) applied for: $(printf '%s' "$touched_skills" | tr '\n' ' ')"
  exit 0
fi

# Verify PR body names at least one valid Eval record directory under <evals_dir>/results/.
esc_evals=$(printf '%s' "$evals_dir" | sed 's/[\/&]/\\&/g')
records=$(sed -nE "s/^Eval record:[[:space:]]*(${esc_evals}\/results\/[A-Za-z0-9._-]+)\/?[[:space:]]*\$/\1/p" "$body_file")
if [ -z "$records" ]; then
  echo "FAIL: promoted skill(s) changed without 'Eval record: ${evals_dir}/results/<dir>' in PR body:" >&2
  while IFS= read -r sk; do
    [ -n "$sk" ] && printf '  - %s\n' "$sk" >&2
  done <<< "$touched_skills"
  exit 1
fi

errors=0
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  case "$rec" in
    *..*|*/.|*/..)
      echo "FAIL: invalid eval record path '$rec' (path traversal forbidden)" >&2
      errors=$((errors + 1))
      continue
      ;;
  esac
  if ! git cat-file -e "${head_rev}:${rec}/benchmark.json" 2>/dev/null && ! git cat-file -e "${head_rev}:${rec}/triggering.json" 2>/dev/null; then
    echo "FAIL: named eval record '$rec' at commit '$head_rev' does not contain benchmark.json or triggering.json" >&2
    errors=$((errors + 1))
  fi
done <<< "$records"

[ "$errors" -eq 0 ] || exit 1
echo "ok: eval records verified for promoted skill(s): $(printf '%s' "$touched_skills" | tr '\n' ' ')"
