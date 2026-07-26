#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/stream-bench.sh" START_ZK
"$SCRIPT_DIR/stream-bench.sh" START_REDIS
PARTITIONS="${1:-32}" "$SCRIPT_DIR/stream-bench.sh" START_KAFKA
"$SCRIPT_DIR/stream-bench.sh" START_FLINK
"$SCRIPT_DIR/stream-bench.sh" START_FLINK_PROCESSING
