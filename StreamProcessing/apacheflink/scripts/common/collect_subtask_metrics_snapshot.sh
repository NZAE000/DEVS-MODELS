#!/usr/bin/env bash
set -Eeuo pipefail

wait_job_creation()
{
    local job_id=""
    while [[ -z "$job_id" || "$job_id" == "null" ]]
    do
        job_id=$(bash "$COMMON_DIR/get_job_id.sh")
        [[ -z "$job_id" || "$job_id" == "null" ]] && sleep 1
    done
    printf '%s\n' "$job_id"
}

wait_running_state()
{
    local state=""
    while true
    do
        state=$(bash "$COMMON_DIR/get_query.sh" "$JOB_ID" | jq -r '.state // empty')
        echo "State: $state"
        case "$state" in
            RUNNING) break ;;
            FAILED|CANCELED|SUSPENDED)
                echo "Job terminated with state: $state" >&2
                return 1
                ;;
            *) sleep 1 ;;
        esac
    done
}

get_operator_list()
{
    local operator_id
    local operator_name

    mapfile -t SUBTASK_IDS < <(
        bash "$COMMON_DIR/get_query.sh" "$JOB_ID" |
        jq -r '.vertices[].id'
    )

    for operator_id in "${SUBTASK_IDS[@]}"
    do
        operator_name=$(
            bash "$COMMON_DIR/get_query.sh" "$JOB_ID/vertices/$operator_id" |
            jq -r '.name'
        )
        SUBTASK_NAMES+=("$operator_name")
    done
}

get_requested_metric_names()
{
    local operator_id=$1
    local subtask_index=$2

    bash "$COMMON_DIR/get_query.sh" \
        "$JOB_ID/vertices/$operator_id/subtasks/$subtask_index/metrics" |
    jq -r '
        [
            .. | objects | .id?
            | select(type == "string")
            | select(
                endswith("numRecordsIn")
                or endswith("numRecordsOut")
                or endswith("accumulateBusyTimeMs")
                or endswith("accumulateIdleTimeMs")
                or endswith("accumulateBackPressuredTimeMs")
                or endswith("softBackPressuredTimeMsPerSecond")
                or endswith("hardBackPressuredTimeMsPerSecond")
                or endswith("isBackPressured")
                or endswith("mailboxQueueSize")
                or endswith("numFiredTimers")
                or contains("operatorRecordInvocation")
                or contains("sourceRecordInvocation")
                or contains("sourceGenerationTimeNs")
                or contains("sourceEmitTimeNs")
                or contains("sourceFrameworkTimeNs")
                or contains("sourceRateWait")
                or contains("sourceIdleTime")
            )
        ]
        | unique[]
    '
}

urlencode()
{
    local value=$1
    jq -nr --arg value "$value" '$value | @uri'
}

query_metric_chunk()
{
    local operator_id=$1
    local subtask_index=$2
    local requested_metrics=$3
    local encoded_metrics
    local response="[]"
    local attempt
    local -r max_attempts=5

    encoded_metrics=$(urlencode "$requested_metrics")

    for ((attempt = 1; attempt <= max_attempts; attempt++))
    do
        response=$(
            bash "$COMMON_DIR/get_query.sh" \
                "$JOB_ID/vertices/$operator_id/subtasks/$subtask_index/metrics?get=$encoded_metrics" \
                2>/dev/null || printf '[]'
        )

        if jq -e '
            [
                .. | objects
                | select(has("id") and has("value"))
            ]
            | length > 0
        ' >/dev/null 2>&1 <<< "$response"; then
            break
        fi

        #sleep 0.1
    done

    jq '
        [
            .. | objects
            | select(has("id") and has("value"))
            | {id: .id, value: .value}
        ]
    ' <<< "$response"
}

get_subtask_metrics()
{
    local operator_id=$1
    local subtask_index=$2
    local metric_name
    local requested_metrics
    local chunk_response
    local index
    local -a metric_names=()
    local -a chunk=()
    local -a responses=()
    local -r chunk_size=15

    mapfile -t metric_names < <(
        get_requested_metric_names "$operator_id" "$subtask_index"
    )

    if [[ ${#metric_names[@]} -eq 0 ]]; then
        printf '[]\n'
        return
    fi

    for metric_name in "${metric_names[@]}"
    do
        chunk+=("$metric_name")

        if [[ ${#chunk[@]} -eq $chunk_size ]]; then
            requested_metrics=$(IFS=,; printf '%s' "${chunk[*]}")
            chunk_response=$(
                query_metric_chunk \
                    "$operator_id" \
                    "$subtask_index" \
                    "$requested_metrics"
            )
            responses+=("$chunk_response")
            chunk=()
        fi
    done

    if [[ ${#chunk[@]} -gt 0 ]]; then
        requested_metrics=$(IFS=,; printf '%s' "${chunk[*]}")
        chunk_response=$(
            query_metric_chunk \
                "$operator_id" \
                "$subtask_index" \
                "$requested_metrics"
        )
        responses+=("$chunk_response")
    fi

    printf '%s\n' "${responses[@]}" |
    jq -s 'add | unique_by(.id)'
}

get_subtask_details()
{
    local operator_id=$1
    local subtask_index=$2

    bash "$COMMON_DIR/get_query.sh" \
        "$JOB_ID/vertices/$operator_id/subtasks/$subtask_index"
}

capture_snapshot()
{
    local timestamp_ms
    local operator_name
    local operator_id
    local parallelism
    local subtask_index
    local metrics_response
    local subtask_details
    local start_time
    local duration_ms
    local operator_entry
    local snapshot_entry
    local i
    local -a operator_entries=()

    timestamp_ms=$(date +%s%3N)

    for ((i = 0; i < ${#SUBTASK_IDS[@]}; i++))
    do
        operator_id=${SUBTASK_IDS[$i]}
        operator_name=${SUBTASK_NAMES[$i]}

        parallelism=$(
            bash "$COMMON_DIR/get_query.sh" "$JOB_ID/vertices/$operator_id" |
            jq -r '.parallelism'
        )

        for ((subtask_index = 0; subtask_index < parallelism; subtask_index++))
        do
            metrics_response=$(
                get_subtask_metrics \
                    "$operator_id" \
                    "$subtask_index"
            )

            subtask_details=$(
                get_subtask_details \
                    "$operator_id" \
                    "$subtask_index"
            )

            start_time=$(jq -r '."start-time" // 0' <<< "$subtask_details")
            duration_ms=$(jq -r '.duration // 0' <<< "$subtask_details")

            operator_entry=$(
                jq -cn \
                    --arg operator "$operator_name" \
                    --arg vertex_id "$operator_id" \
                    --argjson subtask "$subtask_index" \
                    --argjson start_time "$start_time" \
                    --argjson duration_ms "$duration_ms" \
                    --argjson metrics "$metrics_response" \
                    '{
                        operator: $operator,
                        vertex_id: $vertex_id,
                        subtask: $subtask,
                        start_time: $start_time,
                        duration_ms: $duration_ms,
                        metrics: $metrics
                    }'
            )

            operator_entries+=("$operator_entry")
        done
    done

    snapshot_entry=$(
        printf '%s\n' "${operator_entries[@]}" |
        jq -s \
            --argjson snapshot_id "$SNAPSHOT_ID" \
            --argjson timestamp_ms "$timestamp_ms" \
            '{
                snapshot_id: $snapshot_id,
                timestamp_ms: $timestamp_ms,
                operators: .
            }'
    )

    SNAPSHOTS+=("$snapshot_entry")
    SNAPSHOT_ID=$((SNAPSHOT_ID + 1))
}

collect_snapshots()
{
    local state=""

    while true
    do
        state=$(bash "$COMMON_DIR/get_query.sh" "$JOB_ID" | jq -r '.state // empty')

        case "$state" in
            FINISHED)
                capture_snapshot
                break
                ;;
            FAILED|CANCELED|SUSPENDED)
                echo "Job terminated with state: $state" >&2
                return 1
                ;;
            *)
                capture_snapshot
                sleep "$SNAPSHOT_INTERVAL_SECONDS"
                ;;
        esac
    done
}

export_snapshots()
{
    mkdir -p "$OUTPUT_DIR"
    printf '%s\n' "${SNAPSHOTS[@]}" |
    jq -s '.' > "$OUTPUT_FILE"
}

## MAIN #################################

DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly DIR_BASE

COMMON_DIR="$DIR_BASE/../common"
readonly COMMON_DIR

cd "$DIR_BASE" || exit 1

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <snapshot_interval_ms>" >&2
    exit 1
fi

SNAPSHOT_INTERVAL_MS=$1

if ! [[ "$SNAPSHOT_INTERVAL_MS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: snapshot_interval_ms must be a positive integer." >&2
    exit 1
fi

SNAPSHOT_INTERVAL_SECONDS=$(
    awk -v interval_ms="$SNAPSHOT_INTERVAL_MS" \
        'BEGIN { printf "%.3f", interval_ms / 1000 }'
)

readonly SNAPSHOT_INTERVAL_MS
readonly SNAPSHOT_INTERVAL_SECONDS

JOB_ID=$(wait_job_creation)
readonly JOB_ID

echo "Job ID detected: $JOB_ID"

wait_running_state

SUBTASK_NAMES=()
SUBTASK_IDS=()
get_operator_list

OUTPUT_DIR="$DIR_BASE/../../subtasks"
OUTPUT_FILE="$OUTPUT_DIR/subtask_metrics_snapshots.json"
readonly OUTPUT_DIR
readonly OUTPUT_FILE

SNAPSHOTS=()
SNAPSHOT_ID=0

echo "Collecting subtask metrics snapshots..."
collect_snapshots
export_snapshots

echo "Subtask metrics snapshots exported to: $OUTPUT_FILE"