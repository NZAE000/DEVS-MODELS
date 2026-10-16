#!/usr/bin/env bash

set -Eeuo pipefail

if [ $# -ne 3 ]; then
    echo "Usage: $0 <parallelism> <events> <tps>"
    exit 1
fi

PARALLELISM="$1"
EVENTS="$2"
TPS="$3"

DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
YAHOO_DIR="$DIR_BASE/../../yahoo-ads"

readonly KAFKA_PARTITIONS=32

# Workload.
bash "$YAHOO_DIR/update-workloadbyreq.sh" \
    "$EVENTS" \
    "$TPS"

# Yahoo Ads topology configuration.
bash "$YAHOO_DIR/update-app-cfg.sh" \
    "$KAFKA_PARTITIONS" \
    "$PARALLELISM" \
    "$PARALLELISM" \
    "$PARALLELISM" \
    "$PARALLELISM" \
    "$PARALLELISM" \
    "$PARALLELISM"