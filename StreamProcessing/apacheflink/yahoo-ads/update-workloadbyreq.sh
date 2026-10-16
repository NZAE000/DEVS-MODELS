#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKLOAD_FILE="$SCRIPT_DIR/conf/workloadbyreq.txt"

if (( $# == 0 || $# % 2 != 0 )); then
    echo "Usage:"
    echo "  $0 <events1> <tps1> [<events2> <tps2> ...]"
    exit 1
fi

TMP_FILE="${WORKLOAD_FILE}.tmp"

> "$TMP_FILE"

while (( $# > 0 )); do
    EVENTS="$1"
    TPS="$2"

    if ! [[ "$EVENTS" =~ ^[1-9][0-9]*$ ]]; then
        echo "[ERROR] EVENTS must be a positive integer: $EVENTS" >&2
        rm -f "$TMP_FILE"
        exit 1
    fi

    if ! [[ "$TPS" =~ ^[1-9][0-9]*$ ]]; then
        echo "[ERROR] TPS must be a positive integer: $TPS" >&2
        rm -f "$TMP_FILE"
        exit 1
    fi

    printf "%s %s\n" "$EVENTS" "$TPS" >> "$TMP_FILE"

    shift 2
done

mv "$TMP_FILE" "$WORKLOAD_FILE"

echo "[INFO] Workloads updated:"
cat "$WORKLOAD_FILE"