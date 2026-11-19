#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p .test-logs
python3 -m tests.run
python3 -m tests.cleanup 2>>.test-logs/cleanup.log
