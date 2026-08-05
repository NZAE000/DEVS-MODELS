#!/usr/bin/env bash

set -Eeuo pipefail

subtask_name=$1
subtask_index=$2
list_metric_names=$3

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

job_id=$(bash "$DIR_BASE/../common/get_job_id.sh")
operator_id=$(bash "$DIR_BASE/../common/get_subtask_id.sh" "$subtask_name")

encoded_metrics=$(
    printf '%s' "$list_metric_names" |
    jq -sRr @uri
)

bash "$DIR_BASE/../common/get_query.sh" \
    "$job_id/vertices/$operator_id/subtasks/$subtask_index/metrics?get=$encoded_metrics"