#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 7 ]]; then
    echo "Use: bash execute_and_log_dynamic_metrics.sh <app> <n_machines> <cores> <taskslots> <parallelism> <events> <tps>"
    exit 1
fi

APP_NAME="$1"
NUM_MACHINES="$2"
NUM_CORES="$3"
TASKSLOTS="$4"
PARALLELISM="$5"
EVENTS="$6"
TPS="$7"

# ============================
# Paths
# ============================
DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

COMMON_DIR="$DIR_BASE/../common"
YAHOO_DIR="$DIR_BASE/../../yahoo-ads"

THROUGHPUT_PATH="$DIR_BASE/../../../metrics/yahoo/throughput/real/dynamic"
UTILIZATION_PATH="$DIR_BASE/../../../metrics/yahoo/utilization/real/dynamic"
CPU_UTIL_PATH="$DIR_BASE/../../../metrics/yahoo/cpu_util/real/dynamic"

mkdir -p "$THROUGHPUT_PATH" "$UTILIZATION_PATH" "$CPU_UTIL_PATH"

THROUGHPUT_OUTFILE="$THROUGHPUT_PATH/dynamic-throughput-real-${APP_NAME}-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}.txt"
UTILIZATION_OUTFILE="$UTILIZATION_PATH/dynamic-utilization-real-${APP_NAME}-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}.txt"
CPU_UTIL_OUTFILE="$CPU_UTIL_PATH/dynamic-cpu-real-${APP_NAME}-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}.txt"

SUMMARY_FILE="$YAHOO_DIR/run/dynamic-experiment-summary.tsv"

RAW_THROUGHPUT=$(mktemp)
RAW_UTILIZATION=$(mktemp)
RAW_CPU=$(mktemp)

WORKLOAD_PID=""
CURRENT_REQS=-1

declare -A BASE_BUSY_MAP
declare -a OPERATORS

cleanup() {
    rm -f "$RAW_THROUGHPUT" "$RAW_UTILIZATION" "$RAW_CPU"
}

trap cleanup EXIT

# ========================================================
# Normalize operator names exactly as the common scripts
# ========================================================
normalize() {
    echo "$1" |
        tr -d '_[]: ' |
        tr '[:upper:]' '[:lower:]'
}

# ========================================================
# Get aggregated live metric
#
# Returns:
#   numeric value
#   NA if metric cannot be obtained after retries
# ========================================================
get_metric_value() {
    local opername="$1"
    local metric="$2"
    local aggregation="$3"
    local output=""
    local value=""
    local column=""
    local attempt
    local -r max_attempts=10
    local -r retry_sleep=0.5

    case "$aggregation" in
        sum) column=2 ;;
        avg) column=3 ;;
        min) column=4 ;;
        max) column=5 ;;
        *)
            echo "[ERROR] Invalid metric aggregation: $aggregation" >&2
            echo "NA"
            return 0
            ;;
    esac

    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        output="$(
            JOB_ID_OVERRIDE="$JOB_ID" \
            RAW_OUTPUT=true \
            bash "$COMMON_DIR/get_subtask_metrics_acc.sh" \
                "$opername" "$metric" "$aggregation" \
                2>/dev/null || printf '[]'
        )"

        value="$(
            jq -r \
                --arg metric "$metric" \
                --arg aggregation "$aggregation" '
                    [
                        .[]
                        | select(.id == $metric)
                        | .[$aggregation]
                    ][0] // empty
                ' <<< "$output" \
            2>/dev/null || true
        )"

        if [[ -n "$value" && "$value" != "null" ]]; then
            printf '%s\n' "$value"
            return 0
        fi

        #echo \
        #    "[DEBUG] Metric $metric_name for $subtask_name unavailable " \
        #    "(attempt $attempt/$max_attempts): $output" \
        #    >&2

        sleep "$retry_sleep"
    done

    echo "[WARNING] Metric '$metric' unavailable for '$opername' after $max_attempts attempts." >&2
    echo "NA"
}

# ========================================================
# CPU utilization sample
#
# Output is kept in percentage [0,100], matching the
# previous dynamic script.
# ========================================================
get_cpu_utilization() {
    local value

    value="$(
        mpstat -P ALL 1 1 2>/dev/null |
        awk '
            $2 == "all" && $NF ~ /^[0-9]+([.][0-9]+)?$/ {
                value = 100.0 - $NF
            }
            END {
                if (value != "")
                    printf "%.6f", value
            }
        '
    )"

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "NA"
    fi
}

# ============================
# Configure experiment
# ============================
bash "$COMMON_DIR/update_flink_cfg.sh" "$TASKSLOTS" "$PARALLELISM"
bash "$DIR_BASE/update_yahoo_cfg.sh" "$PARALLELISM" "$EVENTS" "$TPS"

# ============================
# Reset and start Yahoo
# ============================
bash "$DIR_BASE/shutdown_and_stop.sh" && bash "$DIR_BASE/start_and_setup.sh"

# ============================
# Get Yahoo Job ID
# ============================
JOB_ID=""

while [[ -z "$JOB_ID" || "$JOB_ID" == "null" ]]; do
    JOB_ID="$(bash "$COMMON_DIR/get_job_id.sh" 2>/dev/null || true)"

    if [[ -z "$JOB_ID" || "$JOB_ID" == "null" ]]; then
        sleep 1
    fi
done

echo "[INFO] Yahoo-Ads Job ID: $JOB_ID"

# ============================
# Wait RUNNING state
# ============================
while true; do
    STATE="$(
        bash "$COMMON_DIR/get_query.sh" "$JOB_ID" 2>/dev/null |
        jq -r '.state // empty' || true
    )"

    echo "State: $STATE"

    if [[ "$STATE" == "RUNNING" ]]; then
        break
    fi

    if [[ "$STATE" == "FAILED" || "$STATE" == "CANCELED" ]]; then
        echo "[ERROR] Yahoo-Ads job entered state '$STATE'."
        exit 1
    fi

    sleep 1
done

# ============================
# Get operator names
# ============================
mapfile -t OPERATORS < <(
    bash "$COMMON_DIR/get_query.sh" "$JOB_ID" |
    jq -r '.vertices[].name' |
    while IFS= read -r opname; do
        normalize "$opname"
    done |
    awk '!seen[$0]++'
)

if [[ ${#OPERATORS[@]} -eq 0 ]]; then
    echo "[ERROR] Could not obtain Yahoo operator names."
    exit 1
fi

echo "[INFO] Operators:"
printf "       %s\n" "${OPERATORS[@]}"

# ========================================================
# Baseline source records
#
# Yahoo job is already RUNNING before the producer starts,
# therefore all cumulative metrics must be baseline-adjusted.
# ========================================================
BASE_SOURCE_RECORDS="$(get_metric_value "sourcekafkasource" "numRecordsOut" "sum")"

if [[ "$BASE_SOURCE_RECORDS" == "NA" ]]; then
    echo "[ERROR] Could not obtain source numRecordsOut baseline."
    exit 1
fi

BASE_SOURCE_RECORDS="$(
    awk -v x="$BASE_SOURCE_RECORDS" '
        BEGIN { printf "%.0f", x + 0 }
    '
)"

# ========================================================
# Baseline exactAccumulateBusyTimeMs for every operator
# ========================================================
for opername in "${OPERATORS[@]}"; do
    BASE_BUSY_MS="$(get_metric_value "$opername" "exactAccumulateBusyTimeMs" "avg")"

    if [[ "$BASE_BUSY_MS" == "NA" ]]; then
        echo "[ERROR] Could not obtain exactAccumulateBusyTimeMs baseline for '$opername'."
        exit 1
    fi

    BASE_BUSY_MAP["$opername"]="$BASE_BUSY_MS"
done

echo "[INFO] Dynamic metric baselines captured."
echo "[INFO] Source records baseline: $BASE_SOURCE_RECORDS"

for opername in "${OPERATORS[@]}"; do
    printf "[INFO] Busy baseline %-25s = %s ms\n" \
        "$opername" "${BASE_BUSY_MAP[$opername]}"
done

# Remove previous summary so an old experiment cannot be read.
rm -f "$SUMMARY_FILE"

# ========================================================
# Start Yahoo workload
#
# Baselines have already been captured immediately before
# producer startup.
# ========================================================
echo "[INFO] Starting Yahoo workload..."

bash "$DIR_BASE/run-workload.sh" &
WORKLOAD_PID=$!

# ========================================================
# Dynamic sampling
#
# Raw samples use epoch milliseconds.
# At the end they are rebased using the actual producer
# start_ms and pipeline_end_ms recorded by Yahoo.
# ========================================================
while true; do
    STATE="$(
        bash "$COMMON_DIR/get_query.sh" "$JOB_ID" 2>/dev/null |
        jq -r '.state // empty' || true
    )"

    if [[ "$STATE" == "FINISHED" ]]; then
        break
    fi

    if [[ "$STATE" == "FAILED" || "$STATE" == "CANCELED" ]]; then
        echo "[ERROR] Yahoo-Ads job entered state '$STATE'."

        if [[ -n "$WORKLOAD_PID" ]]; then
            wait "$WORKLOAD_PID" 2>/dev/null || true
        fi

        exit 1
    fi

    SAMPLE_TIME_MS="$(date +%s%3N)"

    # ====================================================
    # Source records
    # ====================================================
    SOURCE_RECORDS="$(
        get_metric_value \
            "sourcekafkasource" \
            "numRecordsOut" \
            "sum"
    )"

    if [[ "$SOURCE_RECORDS" != "NA" ]]; then
        SOURCE_RECORDS="$(
            awk -v x="$SOURCE_RECORDS" '
                BEGIN { printf "%.0f", x + 0 }
            '
        )"

        TOTAL_REQ=$((SOURCE_RECORDS - BASE_SOURCE_RECORDS))

        if (( TOTAL_REQ < 0 )); then
            TOTAL_REQ=0
        fi

        # Only register throughput when the processed count changes.
        if [[ "$CURRENT_REQS" != "$TOTAL_REQ" ]]; then
            CURRENT_REQS="$TOTAL_REQ"
            printf "%s %s\n" \
                "$SAMPLE_TIME_MS" "$TOTAL_REQ" \
                >> "$RAW_THROUGHPUT"
        fi
    fi

    # ====================================================
    # Operator exact accumulated busy time
    # ====================================================
    for opername in "${OPERATORS[@]}"; do
        CURRENT_BUSY_MS="$(
            get_metric_value \
                "$opername" \
                "exactAccumulateBusyTimeMs" \
                "avg"
        )"

        if [[ "$CURRENT_BUSY_MS" == "NA" ]]; then
            continue
        fi

        BASE_BUSY_MS="${BASE_BUSY_MAP[$opername]}"
        BUSY_DELTA_MS="$(
            awk \
                -v current="$CURRENT_BUSY_MS" \
                -v base="$BASE_BUSY_MS" '
            BEGIN {
                delta = current - base

                if (delta < 0)
                    delta = 0

                printf "%.6f", delta
            }'
        )"

        printf "%s %s %s\n" \
            "$SAMPLE_TIME_MS" \
            "$opername" \
            "$BUSY_DELTA_MS" \
            >> "$RAW_UTILIZATION"
    done

    # ====================================================
    # CPU utilization
    # ====================================================
    CPU_UTIL="$(get_cpu_utilization)"
    CPU_TIME_MS="$(date +%s%3N)"

    if [[ "$CPU_UTIL" != "NA" ]]; then
        printf "%s %s\n" \
            "$CPU_TIME_MS" "$CPU_UTIL" \
            >> "$RAW_CPU"
    fi
done

# ============================
# Wait workload wrapper
# ============================
if ! wait "$WORKLOAD_PID"; then
    WORKLOAD_STATUS=$?
    echo "[ERROR] Yahoo workload finished with status $WORKLOAD_STATUS."
    exit "$WORKLOAD_STATUS"
fi

# ========================================================
# Read actual experimental boundaries
#
# Expected summary format:
#
# requests start_ms emission_end_ms pipeline_end_ms
# finish_time_s drain_time_s throughput
# ========================================================
if [[ ! -f "$SUMMARY_FILE" ]]; then
    echo "[ERROR] Dynamic experiment summary not found:"
    echo "        $SUMMARY_FILE"
    exit 1
fi

read -r \
    SUMMARY_EVENTS \
    START_MS \
    EMISSION_END_MS \
    PIPELINE_END_MS \
    FINISH_TIME \
    DRAIN_TIME \
    SUMMARY_THROUGHPUT \
    < <(
        awk 'NR == 2 {
            print $1, $2, $3, $4, $5, $6, $7
            exit
        }' "$SUMMARY_FILE"
    )

if [[ -z "${START_MS:-}" ||
      -z "${PIPELINE_END_MS:-}" ||
      -z "${FINISH_TIME:-}" ||
      -z "${SUMMARY_THROUGHPUT:-}" ]]; then

    echo "[ERROR] Invalid dynamic experiment summary:"
    cat "$SUMMARY_FILE"
    exit 1
fi

if [[ "$SUMMARY_EVENTS" != "$EVENTS" ]]; then
    echo "[WARNING] Event count in dynamic summary differs from execute arguments."
    echo "          Argument: $EVENTS"
    echo "          Summary:  $SUMMARY_EVENTS"
fi

echo "[INFO] Experimental start:       $START_MS ms"
echo "[INFO] Producer emission end:    $EMISSION_END_MS ms"
echo "[INFO] Pipeline completion:      $PIPELINE_END_MS ms"
echo "[INFO] Experimental finish time: $FINISH_TIME s"
echo "[INFO] Experimental throughput:  $SUMMARY_THROUGHPUT req/s"

# ========================================================
# Write dynamic throughput
#
# Dynamic throughput:
#
#   TP(t) =
#       (sourceRecordsOut(t) - sourceRecordsOut(t0))
#       / (t - t0)
#
# Only samples inside:
#
#   start_ms <= t <= pipeline_end_ms
#
# are retained.
# ========================================================
printf "%s:" "$TPS" > "$THROUGHPUT_OUTFILE"

awk \
    -v start="$START_MS" \
    -v finish="$PIPELINE_END_MS" '
$1 >= start && $1 <= finish {
    elapsed_ms = $1 - start

    if (elapsed_ms > 0) {
        elapsed_s = elapsed_ms / 1000.0
        throughput = $2 / elapsed_s

        printf "%.6f,%.6f ", elapsed_s, throughput
    }
}
' "$RAW_THROUGHPUT" >> "$THROUGHPUT_OUTFILE"

# Add the exact experimental endpoint obtained from the
# pipeline completion summary.
printf "%.6f,%.6f\n" \
    "$FINISH_TIME" \
    "$SUMMARY_THROUGHPUT" \
    >> "$THROUGHPUT_OUTFILE"

# ========================================================
# Write dynamic operator utilization
#
# Uop(t) =
#
#   [exactBusyAvg(t) - exactBusyAvg(t0)]
#   ------------------------------------
#                  t - t0
#
# exactAccumulateBusyTimeMs is aggregated using avg, so
# division by P is already represented by the aggregation.
# ========================================================
echo "$TPS" > "$UTILIZATION_OUTFILE"

for opername in "${OPERATORS[@]}"; do
    printf "%s:[" "$opername" >> "$UTILIZATION_OUTFILE"

    awk \
        -v op="$opername" \
        -v start="$START_MS" \
        -v finish="$PIPELINE_END_MS" '
    $2 == op && $1 >= start && $1 <= finish {
        elapsed_ms = $1 - start

        if (elapsed_ms > 0) {
            utilization = $3 / elapsed_ms

            if (utilization < 0)
                utilization = 0

            printf "%.8f ", utilization
        }
    }
    ' "$RAW_UTILIZATION" >> "$UTILIZATION_OUTFILE"

    echo "]" >> "$UTILIZATION_OUTFILE"
done

# ========================================================
# Write dynamic CPU utilization
#
# Format preserved from the old dynamic script:
#
# TPS:time,cpu% time,cpu% ...
# ========================================================
printf "%s:" "$TPS" > "$CPU_UTIL_OUTFILE"

awk \
    -v start="$START_MS" \
    -v finish="$PIPELINE_END_MS" '
$1 >= start && $1 <= finish {
    elapsed_ms = $1 - start

    if (elapsed_ms > 0) {
        elapsed_s = elapsed_ms / 1000.0
        printf "%.6f,%.6f ", elapsed_s, $2
    }
}
' "$RAW_CPU" >> "$CPU_UTIL_OUTFILE"

echo "" >> "$CPU_UTIL_OUTFILE"

# ============================
# Confirmation
# ============================
echo ""
echo "Dynamic metrics successfully written to:"
echo "'$THROUGHPUT_OUTFILE'"
echo "'$UTILIZATION_OUTFILE'"
echo "'$CPU_UTIL_OUTFILE'"