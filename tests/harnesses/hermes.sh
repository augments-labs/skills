#!/usr/bin/env bash
# Hermes Agent driver. Sourced by tests/run-plugin-smoke.sh, never executed.
# `hermes plugins install` clones a Git repository and copies one
# subdirectory, the path a user's `owner/repo/plugins/<plugin>` install takes.
# The driver commits a snapshot of the tree under test and installs
# file://<snapshot>#plugins/<plugin> under an isolated HOME and HERMES_HOME.
# No credentials are needed.
#
# Hermes scans the copy before installing and rates the bundled hook scripts
# (which Hermes never runs; they name sudo to recognize it in commands) as
# caution. A user confirms at the prompt; this non-interactive run passes
# --force, which overrides a caution verdict but never a dangerous one.

adapter_check() {
  command -v hermes >/dev/null 2>&1 || { echo "no \`hermes\` CLI on PATH" >&2; return 3; }
  command -v git >/dev/null 2>&1 || { echo "no \`git\` on PATH" >&2; return 3; }
}

# `hermes --version` only runs against Hermes's own home, where it writes, so
# the version is read from the isolated install instead (see adapter_install).
adapter_version() { echo "version read after install"; }

hermes_env() {
  (cd "$harness_home/work" &&
    env -i PATH="$PATH" HOME="$harness_home" HERMES_HOME="$harness_home" GIT_CONFIG_NOSYSTEM=1 TERM=dumb "$@" </dev/null)
}

adapter_install() { # $1 repo root, $2 plugin name
  local snap
  harness_home="$(mktemp -d)"
  snap="$harness_home/snapshot"
  mkdir -p "$harness_home/work" "$snap"
  (cd "$1" && git ls-files -co --exclude-standard | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s\n' "$f"; fi
  done | tar -cf - -T -) | tar -xf - -C "$snap" || { echo "could not copy $1" >>"$errlog"; return 1; }
  hermes_env sh -c 'cd "$1" && git init -q && git add -A &&
    git -c user.name=smoke -c user.email=smoke@localhost -c commit.gpgsign=false commit -qm snapshot' \
    sh "$snap" >>"$errlog" 2>&1 || { echo "could not commit the snapshot" >>"$errlog"; return 1; }
  hermes_env hermes plugins install "file://$snap#plugins/$2" --enable --yes-deps --force >>"$errlog" 2>&1 || {
    echo "hermes plugins install failed" >>"$errlog"; return 1; }
  echo "        version: $(hermes_env hermes --version 2>&1 | head -n 1)"
}

# The skills Hermes itself puts in the prompt (plugin skills are <plugin>:<skill>).
adapter_inventory() { # $1 plugin name
  hermes_env hermes prompt-size --json 2>>"$errlog" |
    jq -r --arg p "$1:" '.skills_breakdown[]? | .name | select(startswith($p)) | ltrimstr($p)' 2>>"$errlog"
}
