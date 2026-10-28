#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 8 ]]; then
    echo "Use: bash execute_and_log_metrics.sh <app> <app_dir> <n_machines> <cores> <taskslots> <parallelism> <events> <tps>"
    exit 1
fi

APP_NAME="$1"
APP_DIR="$2"
NUM_MACHINES="$3"
NUM_CORES="$4"
TASKSLOTS="$5"
PARALLELISM="$6"
EVENTS="$7"
TPS="$8"

# ============================
# Get absolute path and locate.
# ============================
DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

THROUGHPUT_PATH="$DIR_BASE/../../../metrics/${APP_DIR}/throughput/real/terminated"
UTILIZATION_PATH="$DIR_BASE/../../../metrics/${APP_DIR}/utilization/real/terminated"

THROUGHPUT_OUTFILE="terminated-throughput-real-${APP_NAME}-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}-${EVENTS}-${TPS}.txt"
UTILIZATION_OUTFILE="terminated-utilization-real-${APP_NAME}-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}-${EVENTS}-${TPS}.txt"

mkdir -p "$THROUGHPUT_PATH" "$UTILIZATION_PATH"

EXEC_OUTPUT=$(mktemp)

# Always remove the temporary output file.
trap 'rm -f "$EXEC_OUTPUT"' EXIT

# ============================
# Execute app
# ============================
#
# execute.sh writes directly to the temporary file. At the same time, tail
# follows that file so the output remains visible in real time.
#
# This avoids using a pipe with tee, which could remain open because of
# background Flink processes inheriting the pipe descriptor.
#
bash "$DIR_BASE/../${APP_DIR}/execute.sh" "$APP_NAME" "$TASKSLOTS" "$PARALLELISM" "$EVENTS" "$TPS" > "$EXEC_OUTPUT" 2>&1 &
EXEC_PID=$!

# Show execute.sh output in real time until the process finishes.
tail --pid="$EXEC_PID" -n +1 -f "$EXEC_OUTPUT"

# Obtain the real exit status of execute.sh.
wait "$EXEC_PID"
EXEC_STATUS=$?

if [[ "$EXEC_STATUS" -ne 0 ]]; then
    exit "$EXEC_STATUS"
fi

# =======================================================
# Extract finishing time and throughput from execute.sh
# =======================================================
read -r FINISH_TIME THROUGHPUT < <(
    awk -F'[:, ]+' '/^FTime:/ { print $2, $5; exit }' "$EXEC_OUTPUT"
)

if [[ -z "$FINISH_TIME" || -z "$THROUGHPUT" ]]; then
    echo "[ERROR] Could not extract finishing time or throughput from execute.sh output."
    exit 1
fi

# ============================
# Store f_time and throughput
# ============================
printf "%.4f %.4f\n" "$FINISH_TIME" "$THROUGHPUT" >> "$THROUGHPUT_PATH/$THROUGHPUT_OUTFILE"

# =======================================================
# Store operator utilization
#
# Input format from execute.sh:
#
#   Operator P InRecords OutRecords Select AccumBusyTime BusyTime Utilization
#
# BusyTime is:
#
#   BusyTime = AccumBusyTime / P
#
# Output format:
#
#   operator1:utilization1;
#   operator2:utilization2;
#   ...
#
# Stored in a single line.
# =======================================================
awk '
$1 == "Operator" && $2 == "P" && $3 == "InRecords" && $4 == "OutRecords" && $5 == "Select" && $6 == "AccumBusyTime" && $7 == "BusyTime" && $8 == "Utilization" {
    operator_table = 1
    next
}

operator_table && NF >= 8 && $2 ~ /^[0-9]+$/ {
    printf "%s:%s;", $1, $8
}

END {
    if (operator_table)
        printf "\n"
}
' "$EXEC_OUTPUT" >> "$UTILIZATION_PATH/$UTILIZATION_OUTFILE"

# ============================
# Show stored records
# ============================
printf "\nRecords added:\n"
printf "\t%s/%s\n\t%s/%s\n" "$THROUGHPUT_PATH" "$THROUGHPUT_OUTFILE" "$UTILIZATION_PATH" "$UTILIZATION_OUTFILE"