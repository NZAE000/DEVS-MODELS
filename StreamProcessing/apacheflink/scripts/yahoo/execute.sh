#!/usr/bin/env bash

set -Eeuo pipefail

TASKSLOTS="$1"
PARALLELISM="$2"
EVENTS="$3"
TPS="$4"

if [ $# -ne 4 ]; then
    echo "Use: bash execute.sh <taskslots> <parallelism> <events> <tps>"
    exit 1
fi

DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

APACHEFLINK_DIR="$DIR_BASE/../.."
COMMON_DIR="$DIR_BASE/../common"
APP_NAME="yahoo-ads"

CPU_LOG="/tmp/cpu_${APP_NAME}_${TASKSLOTS}_${PARALLELISM}_${EVENTS}_${TPS}.log"

# ============================
# Update Flink and Yahoo params
# ============================
bash "$COMMON_DIR/update_flink_cfg.sh" \
    "$TASKSLOTS" \
    "$PARALLELISM"

bash "$DIR_BASE/update_yahoo_cfg.sh" \
    "$PARALLELISM" \
    "$EVENTS" \
    "$TPS"

# ============================
# Stop and initialize
# ============================
bash "$DIR_BASE/shutdown_and_stop.sh"
bash "$DIR_BASE/start_and_setup.sh"

# Preserve job ID before the workload cancels it.
JOB_ID=$(bash "$COMMON_DIR/get_job_id.sh")

if [[ -z "$JOB_ID" || "$JOB_ID" == "null" ]]; then
    echo "[ERROR] Yahoo-Ads job was not found."
    exit 1
fi

echo "[INFO] Yahoo-Ads Job ID: $JOB_ID"

# =======================================
# Start CPU monitoring
# =======================================

mpstat -P ALL 1 > "$CPU_LOG" &
MPSTAT_PID=$!

# ============================
# Execute workload
# ============================

bash "$DIR_BASE/run-workload.sh"

# ============================
# Stop CPU monitoring
# ============================

kill "$MPSTAT_PID" 2>/dev/null || true
wait "$MPSTAT_PID" 2>/dev/null || true

# ============================
# CPU utilization
# ============================

CPU_UTIL=$(awk '
  $2 == "all" {
    idle += $NF
    n++
  }

  END {
    if (n > 0) printf "%.4f", ((100 - (idle / n)) / 100)
    else print "0.0"
  }
' "$CPU_LOG")

rm -f "$CPU_LOG"