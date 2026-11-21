#!/bin/sh
# Stands in for an agent CLI (claude, codex, agy) in the adapter suite: the
# suite symlinks this file under the CLI's name into a scratch bin directory.
# Every call appends its arguments (one per line, then "--") to <name>.argv
# and its environment to <name>.env beside the symlink, and counts itself in
# <name>.calls. Call N then prints <name>.stream.N when that file exists, else
# <name>.stream when that exists, and exits with <name>.rc.N, else <name>.rc,
# else 0.
dir="$(dirname "$0")"
name="$(basename "$0")"
for a in "$@"; do printf '%s\n' "$a"; done >> "$dir/$name.argv"
printf -- '--\n' >> "$dir/$name.argv"
env | LC_ALL=C sort >> "$dir/$name.env"
printf -- '--\n' >> "$dir/$name.env"
case "$1" in
  --version) echo "$name 0.0.0-fake"; exit 0 ;;
esac
n=$(( $(cat "$dir/$name.calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$dir/$name.calls"
if [ -f "$dir/$name.stream.$n" ]; then cat "$dir/$name.stream.$n"
elif [ -f "$dir/$name.stream" ]; then cat "$dir/$name.stream"; fi
if [ -f "$dir/$name.rc.$n" ]; then exit "$(cat "$dir/$name.rc.$n")"; fi
if [ -f "$dir/$name.rc" ]; then exit "$(cat "$dir/$name.rc")"; fi
exit 0
