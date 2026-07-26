#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

workloads_file="$SCRIPT_DIR/conf/workloadbyreq.txt"
drain_seconds="${1:-30}"

WORKLOADS_FILE="$workloads_file" \
DRAIN_SECONDS="$drain_seconds" \
"$SCRIPT_DIR/stream-bench.sh" RUN_DYNAMIC_EXPERIMENT