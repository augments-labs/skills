#!/bin/sh
# Stands in for an agent CLI (claude, codex, agy) in the adapter suite: the
# suite symlinks this file under the CLI's name into a scratch bin directory.
# Every call appends its arguments (one per line, then "--") to <name>.argv
# and its environment to <name>.env beside the symlink, then prints
# <name>.stream when that file exists and exits with <name>.rc (default 0).
dir="$(dirname "$0")"
name="$(basename "$0")"
for a in "$@"; do printf '%s\n' "$a"; done >> "$dir/$name.argv"
printf -- '--\n' >> "$dir/$name.argv"
env | LC_ALL=C sort >> "$dir/$name.env"
printf -- '--\n' >> "$dir/$name.env"
case "$1" in
  --version) echo "$name 0.0.0-fake"; exit 0 ;;
esac
if [ -f "$dir/$name.stream" ]; then cat "$dir/$name.stream"; fi
if [ -f "$dir/$name.rc" ]; then exit "$(cat "$dir/$name.rc")"; fi
exit 0
