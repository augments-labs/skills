#!/usr/bin/env bash
# Prints the usage percentage of the filesystem holding /srv.
df -P "${1:-/srv}" | awk 'NR == 2 { sub(/%/, "", $5); print $5 }'
