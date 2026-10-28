#!/usr/bin/env bash
set -Eeuo pipefail

if [ $# -ne 5 ]; then
    echo "Use: bash execute.sh <app> <taskslots> <parallelism> <events> <tps>"
    exit 1
fi

APP_NAME="$1"
TASKSLOTS="$2"
PARALLELISM="$3"
EVENTS="$4"
TPS="$5"

## Get absolute path and locate.
DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

CPU_LOG="/tmp/cpu_${APP_NAME}_${TASKSLOTS}_${PARALLELISM}_${EVENTS}_${TPS}.log"

# ============================
# Update flink and nexmark parameters
# ============================
bash "$DIR_BASE/../common/update_flink_cfg.sh" $TASKSLOTS $PARALLELISM
bash "$DIR_BASE/update_nexmark_cfg.sh" $EVENTS $TPS

# ============================
# Stop and initialize
# ============================
bash "$DIR_BASE/shutdown_and_stop.sh" && bash "$DIR_BASE/start_and_setup.sh"

# =======================================
# Start CPU monitoring while app execute
# =======================================
mpstat -P ALL 1 > "$CPU_LOG" &
MPSTAT_PID=$!

# ============================
# Execute app
# ============================
bash "$DIR_BASE/run-query.sh" "$APP_NAME"

# ================================
# Kill monitoring when app finish
# ================================
kill "$MPSTAT_PID"

# ================================
# Calculate avg CPU utilization
# ================================
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

rm "$CPU_LOG" # Delete temp
#echo "$CPU_UTIL"

# =======================================================
# Capture timestamps and calculate metrics when app finish
# =======================================================
FLINK_URL="http://localhost:8081"
JOB_ID=$(bash "$DIR_BASE/../common/get_job_id.sh")

if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
    echo "[ERROR] There are no active or completed jobs."
    exit 1
fi

start_time=$(curl -s "${FLINK_URL}/jobs/${JOB_ID}" | jq -r '.timestamps.RUNNING')
end_time=$(curl -s "${FLINK_URL}/jobs/${JOB_ID}" | jq -r '.timestamps.FINISHED')
finish_time_ms=$(echo "$end_time - $start_time" | bc -l)
FINISH_TIME=$(echo "$finish_time_ms / 1000" | bc -l)
THROUGHPUT=$(echo "$EVENTS / $FINISH_TIME" | bc -l)

# =============================================
# Show f_time, throughput and cpu utilization
# =============================================
printf "FTime: %.4f s, Throughput: %.4f req/s, CPUU: %.4f\n" "$FINISH_TIME" "$THROUGHPUT" "$CPU_UTIL"

# =======================================================
# Obtain metrics per operator
# =======================================================

PLAN_JSON="plan_tmp.json"

# Get job with plan.
curl -s "${FLINK_URL}/jobs/${JOB_ID}" > "$PLAN_JSON"

# -------------------------------------------------------------------------------
# Extract data from .vertices[] -> ID, name, parallelism and operator metrics.
# -------------------------------------------------------------------------------

normalize() {
    echo "$1" | tr -d '_[]: ' | tr '[:upper:]' '[:lower:]'
}

TOTAL_ACUM_BUSY_TIME=0.0

echo ""
printf "%-25s %-5s %-15s %-15s %-15s %-15s %-15s %-15s\n" "Operator" "P" "InRecords" "OutRecords" "Select" "AccumBusyTime" "BusyTime" "Utilization"

while IFS=';' read -r OPER_ID RAW_NAME PAR; do
    NAME=$(normalize "$RAW_NAME")

    ###########################################################################
    # ARCHIVED TERMINAL METRICS
    #
    # These metrics belong to the final archived ExecutionGraph state.
    ###########################################################################
    VERTEX_JSON=$(curl -s "${FLINK_URL}/jobs/${JOB_ID}/vertices/${OPER_ID}")

    IN_RECORDS=$(echo "$VERTEX_JSON" | jq -r '
        [.subtasks[].metrics["read-records"] // 0]
        | add // 0
    ')

    OUT_RECORDS=$(echo "$VERTEX_JSON" | jq -r '
        [.subtasks[].metrics["write-records"] // 0]
        | add // 0
    ')

    ARCH_BUSY_MS=$(echo "$VERTEX_JSON" | jq -r '
        [.subtasks[].metrics["accumulated-busy-time"] // 0]
        | add // 0
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
    # BUSY TIME
    #
    # accumulated-busy-time is archived in milliseconds and already represents
    # the sum across all subtasks after adding the individual archived values.
    ###########################################################################
    ACUM_BUSY_TIME=$(echo "$ARCH_BUSY_MS / 1000.0" | bc -l)
    TOTAL_ACUM_BUSY_TIME=$(echo "$TOTAL_ACUM_BUSY_TIME + $ACUM_BUSY_TIME" | bc -l)
    BUSY_TIME=$(echo "$ACUM_BUSY_TIME / $PAR" | bc -l)
    UTILIZATION=$(echo "$BUSY_TIME / $FINISH_TIME" | bc -l)

    printf "%-25s %-5s %-15s %-15s %-15.4f %-15.6f %-15.6f %-15s\n" \
        "$NAME" "$PAR" "$IN_RECORDS" "$OUT_RECORDS" "$SELECTIVITY" "$ACUM_BUSY_TIME" "$BUSY_TIME" "$UTILIZATION"

done < <(
    jq -r '.vertices[] | "\(.id);\(.name);\(.parallelism)"' "$PLAN_JSON"
)

rm "$PLAN_JSON"