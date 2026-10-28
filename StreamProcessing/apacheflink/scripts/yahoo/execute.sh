#!/usr/bin/env bash
set -Eeuo pipefail

if [ $# -ne 5 ]; then
    echo "Use: bash execute.sh <app> <taskslots> <parallelism> <events> <tps>"
    exit 1
fi

APP_NAME="yahoo-ads"
TASKSLOTS="$2"
PARALLELISM="$3"
EVENTS="$4"
TPS="$5"

## Get absolute path and locate.
DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

APACHEFLINK_DIR="$DIR_BASE/../.."
COMMON_DIR="$DIR_BASE/../common"
YAHOO_DIR="$APACHEFLINK_DIR/${APP_NAME}"
FLINK_URL="http://localhost:8081"

JOB_ID_FILE="$YAHOO_DIR/run/flink-job.id"
SUMMARY_FILE="$YAHOO_DIR/run/dynamic-experiment-summary.tsv"
CPU_LOG="/tmp/cpu_${APP_NAME}_${TASKSLOTS}_${PARALLELISM}_${EVENTS}_${TPS}.log"

# ============================
# Update Flink and Yahoo params
# ============================
bash "$COMMON_DIR/update_flink_cfg.sh" "$TASKSLOTS" "$PARALLELISM" && bash "$DIR_BASE/update_yahoo_cfg.sh" "$PARALLELISM" "$EVENTS" "$TPS"

# ============================
# Stop and initialize
# ============================
bash "$DIR_BASE/shutdown_and_stop.sh"
bash "$DIR_BASE/start_and_setup.sh"

# ============================
# Preserve exact Yahoo Job ID
# ============================
if [[ ! -s "$JOB_ID_FILE" ]]; then
    echo "[ERROR] Yahoo-Ads Job ID file was not found: $JOB_ID_FILE"
    exit 1
fi

JOB_ID="$(<"$JOB_ID_FILE")"

if [[ -z "$JOB_ID" ]]; then
    echo "[ERROR] Yahoo-Ads Job ID is empty."
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

# =======================================================
# Read experimental finish time and throughput
# =======================================================
if [[ ! -f "$SUMMARY_FILE" ]]; then
    echo "[ERROR] Dynamic experiment summary not found: $SUMMARY_FILE"
    exit 1
fi

read -r SUMMARY_EVENTS FINISH_TIME DRAIN_TIME THROUGHPUT < <(
    awk -F'\t' 'NR == 2 { print $1, $5, $6, $7; exit }' "$SUMMARY_FILE"
)

if [[ -z "${SUMMARY_EVENTS:-}" || -z "${FINISH_TIME:-}" || -z "${THROUGHPUT:-}" ]]; then
    echo "[ERROR] Invalid dynamic experiment summary:"
    cat "$SUMMARY_FILE"
    exit 1
fi

if [[ "$SUMMARY_EVENTS" != "$EVENTS" ]]; then
    echo "[ERROR] Event count mismatch in dynamic experiment summary."
    echo "        Expected: $EVENTS"
    echo "        Found:    $SUMMARY_EVENTS"
    exit 1
fi

# =======================================================
# Validate final Flink state
# =======================================================
JOB_STATE=$(curl -fsS "${FLINK_URL}/jobs/${JOB_ID}" | jq -r '.state // empty')

if [[ "$JOB_STATE" != "FINISHED" ]]; then
    echo "[ERROR] Yahoo-Ads job did not finish correctly."
    echo "        Job ID: $JOB_ID"
    echo "        State:  $JOB_STATE"
    exit 1
fi

# =============================================
# Show finish time, throughput and CPU
# =============================================
printf "FTime: %.4f s, Throughput: %.4f req/s, CPUU: %.4f\n" \
    "$FINISH_TIME" "$THROUGHPUT" "$CPU_UTIL"

# =======================================================
# Obtain archived terminal metrics per operator
# =======================================================
PLAN_JSON="/tmp/yahoo_plan_${JOB_ID}.json"
curl -fsS "${FLINK_URL}/jobs/${JOB_ID}" > "$PLAN_JSON"

normalize() {
    echo "$1" | tr -d '_[]: ' | tr '[:upper:]' '[:lower:]'
}

TOTAL_ACUM_BUSY_TIME=0.0

echo ""
printf "%-25s %-5s %-15s %-15s %-15s %-15s %-15s %-15s\n" \
    "Operator" "P" "InRecords" "OutRecords" "Select" "AccumBusyTime" "BusyTime" "Utilization"

while IFS=';' read -r OPER_ID RAW_NAME PAR; do
    NAME="$(normalize "$RAW_NAME")"

    ###########################################################################
    # ARCHIVED TERMINAL METRICS
    ###########################################################################
    VERTEX_JSON=$(curl -fsS "${FLINK_URL}/jobs/${JOB_ID}/vertices/${OPER_ID}")

    IN_RECORDS=$(echo "$VERTEX_JSON" | jq -r '
        [.subtasks[].metrics["read-records"] // 0] | add // 0
    ')

    OUT_RECORDS=$(echo "$VERTEX_JSON" | jq -r '
        [.subtasks[].metrics["write-records"] // 0] | add // 0
    ')

    ARCH_BUSY_MS=$(echo "$VERTEX_JSON" | jq -r '
        [.subtasks[].metrics["accumulated-busy-time"] // 0] | add // 0
    ')

    IN_COMPLETE=$(echo "$VERTEX_JSON" | jq -r '
        all(.subtasks[]; .metrics["read-records-complete"] == true)
    ')

    OUT_COMPLETE=$(echo "$VERTEX_JSON" | jq -r '
        all(.subtasks[]; .metrics["write-records-complete"] == true)
    ')

    ###########################################################################
    # VALIDATE ARCHIVED I/O METRICS
    ###########################################################################
    if [[ "$IN_COMPLETE" != "true" || "$OUT_COMPLETE" != "true" ]]; then
        echo "WARNING: incomplete archived I/O metrics for operator $NAME (read-complete=$IN_COMPLETE, write-complete=$OUT_COMPLETE)" >&2
    fi

    ###########################################################################
    # SELECTIVITY
    ###########################################################################
    if [[ "$IN_RECORDS" != "0" ]]; then
        SELECTIVITY=$(echo "$OUT_RECORDS / $IN_RECORDS" | bc -l)
    else
        SELECTIVITY="0.0"
    fi

    ###########################################################################
    # BUSY TIME AND UTILIZATION
    ###########################################################################
    ACUM_BUSY_TIME=$(echo "$ARCH_BUSY_MS / 1000.0" | bc -l)
    TOTAL_ACUM_BUSY_TIME=$(echo "$TOTAL_ACUM_BUSY_TIME + $ACUM_BUSY_TIME" | bc -l)
    BUSY_TIME=$(echo "$ACUM_BUSY_TIME / $PAR" | bc -l)
    UTILIZATION=$(echo "$BUSY_TIME / $FINISH_TIME" | bc -l)

    printf "%-25s %-5s %-15s %-15s %-15.4f %-15.6f %-15.6f %-15s\n" \
        "$NAME" "$PAR" "$IN_RECORDS" "$OUT_RECORDS" "$SELECTIVITY" \
        "$ACUM_BUSY_TIME" "$BUSY_TIME" "$UTILIZATION"

done < <(
    jq -r '.vertices[] | "\(.id);\(.name);\(.parallelism)"' "$PLAN_JSON"
)

rm -f "$PLAN_JSON"