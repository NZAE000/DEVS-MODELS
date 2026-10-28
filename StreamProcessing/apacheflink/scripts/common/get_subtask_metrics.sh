#!/usr/bin/env bash
set -Eeuo pipefail

if [ $# -ne 3 ]; then
    echo "Usage: $0 <subtask_name> <subtask_index> <metrics>" >&2
    exit 1
fi

subtask_name=$1
subtask_index=$2
list_metric_names=${3:-}

# Get absolute path and locate.
DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

job_id=$(bash "$DIR_BASE/../common/get_job_id.sh")
operator_id=$(bash "$DIR_BASE/../common/get_subtask_id.sh" "$subtask_name")

metrics_endpoint="$job_id/vertices/$operator_id/subtasks/$subtask_index/metrics"

if [[ -z "$list_metric_names" ]]; then
    # No metrics specified: show all available metrics.
    bash "$DIR_BASE/../common/get_query.sh" \
        "$metrics_endpoint"
else
    # Metrics specified: request only those metrics.
    encoded_metrics=$(
        printf '%s' "$list_metric_names" |
        jq -sRr @uri
    )

    bash "$DIR_BASE/../common/get_query.sh" \
        "$metrics_endpoint?get=$encoded_metrics"
fi