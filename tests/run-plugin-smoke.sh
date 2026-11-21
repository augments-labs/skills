#!/usr/bin/env bash
# Install smoke test, one runner for every harness driver. No model call.
#
# If a user installs the plugin the way this harness installs plugins, do the
# promoted skills land where the harness looks, and does the harness itself
# resolve exactly that set? Files on disk that the harness never discovers are
# not a working install.
#
# Needs the harness CLI and jq; skipped in CI (run locally before a release).
# Flags and exit codes: --help.

set -uo pipefail
export LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harnessdir="$repo/tests/harnesses"
harness_names="$(cd "$harnessdir" && for f in *.sh; do basename "$f" .sh; done | sort | paste -sd '|' -)"

usage() {
  cat <<EOF
tests/run-plugin-smoke.sh: do the skills land where this harness looks? No model call.

  --harness NAME    ${harness_names//|/ | }   (required)
  --plugin NAME     plugin bundle under plugins/ (default: engineering-skills)
  --sample-skill    install a temporary copy of the repo with one extra
                    promoted sample skill (automatic when no skill is promoted)
  --help            this text

Exit codes: 0 the harness resolved exactly the promoted skills
            1 install failed, or skills are missing, extra, or misplaced
            2 bad or missing arguments · 3 harness CLI or jq unavailable
EOF
}

harness="" plugin="engineering-skills" sample=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --harness) [ "$#" -ge 2 ] || { echo "--harness needs a value" >&2; exit 2; }; harness="$2"; shift 2 ;;
    --plugin) [ "$#" -ge 2 ] || { echo "--plugin needs a value" >&2; exit 2; }; plugin="$2"; shift 2 ;;
    --sample-skill) sample=1; shift ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done
[ -n "$harness" ] || { echo "needs --harness $harness_names" >&2; exit 2; }
[ -f "$harnessdir/$harness.sh" ] || { echo "no harness driver: $harness" >&2; exit 2; }
[ -d "$repo/plugins/$plugin" ] || { echo "no plugin bundle: plugins/$plugin" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "needs \`jq\`" >&2; exit 3; }

# shellcheck source=/dev/null
. "$harnessdir/$harness.sh"
adapter_check || exit 3

errlog="$(mktemp)" harness_home="" plugin_root="" work=""
cleanup() {
  [ -n "$harness_home" ] && rm -rf "$harness_home"
  [ -n "$work" ] && rm -rf "$work"
  rm -f "$errlog"
}
trap cleanup EXIT

pack="${plugin%-skills}"
promoted() { # $1 repo root
  find "$1/skills/$pack" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | sed 's|/SKILL.md$||; s|.*/||' | sort -u
}

source_repo="$repo"
if [ "$sample" -eq 0 ] && [ -z "$(promoted "$repo")" ]; then
  echo "note    : no promoted skills in skills/$pack/; using --sample-skill"
  sample=1
fi
if [ "$sample" -eq 1 ]; then
  work="$(mktemp -d)"
  source_repo="$work/repo"
  mkdir -p "$source_repo"
  (cd "$repo" && git ls-files -co --exclude-standard | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done | tar -cf - -T -) | tar -xf - -C "$source_repo" || { echo "could not copy the repo" >&2; exit 1; }
  mkdir -p "$source_repo/skills/$pack/smoke-sample"
  cat > "$source_repo/skills/$pack/smoke-sample/SKILL.md" <<'EOF'
---
name: smoke-sample
description: "Install smoke sample. Use when checking that a plugin install exposes skills. Skip all real work."
---

# Smoke sample

Temporary skill created by tests/run-plugin-smoke.sh.
EOF
  (cd "$source_repo" && git init -q && bash scripts/sync-plugins.sh >/dev/null) || {
    echo "could not sync the sample copy" >&2; exit 1; }
fi

canonical_names="$(promoted "$source_repo")"
canonical="$(printf '%s\n' "$canonical_names" | grep -c .)"
echo "harness : $harness ($(adapter_version))"
echo "plugin  : $plugin"
echo "skills  : $canonical promoted"

if ! adapter_install "$source_repo" "$plugin"; then
  echo "  FAIL  install failed"; sed 's/^/        /' "$errlog" >&2; exit 1
fi
echo "  ok    install completed"

inventory="$(adapter_inventory "$plugin")" || {
  echo "  FAIL  harness inventory failed"; sed 's/^/        /' "$errlog" >&2; exit 1; }
inventory="$(printf '%s\n' "$inventory" | grep . | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$canonical_names") <(printf '%s\n' "$inventory") | grep .)"
extra="$(comm -13 <(printf '%s\n' "$canonical_names") <(printf '%s\n' "$inventory") | grep .)"
if [ -z "$missing" ] && [ -z "$extra" ]; then
  echo "  ok    harness resolved exactly the $canonical promoted skill(s)"
  echo "plugin smoke: PASS"
  exit 0
fi
echo "  FAIL  harness inventory differs from the promoted set"
[ -n "$missing" ] && printf '%s\n' "$missing" | sed 's/^/        missing: /'
[ -n "$extra" ] && printf '%s\n' "$extra" | sed 's/^/        extra:   /'
[ -s "$errlog" ] && sed 's/^/        /' "$errlog" >&2
echo "plugin smoke: FAIL"
exit 1
