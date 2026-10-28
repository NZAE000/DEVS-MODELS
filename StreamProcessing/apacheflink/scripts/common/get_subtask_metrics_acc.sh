#!/usr/bin/env bash
set -Eeuo pipefail

subtask_name=${1:-}

if [[ -z "$subtask_name" ]]; then
    echo "Usage:"
    echo "  $0 <subtask_name>"
    echo "  $0 <subtask_name> <metrics>"
    echo "  $0 <subtask_name> <metrics> <aggregations>"
    exit 1
fi

metrics=${2:-}
aggregations=${3:-}

DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

JOB_ID="${JOB_ID_OVERRIDE:-$(bash "$DIR_BASE/get_job_id.sh")}"

VERTEX_ID=$(
    JOB_ID_OVERRIDE="$JOB_ID" \
    bash "$DIR_BASE/get_subtask_id.sh" "$subtask_name"
)

if [[ -z "$VERTEX_ID" ]]; then
    echo "Subtask not found: $subtask_name" >&2
    exit 1
fi

# List metric names.
if [[ -z "$metrics" ]]; then
    bash "$DIR_BASE/get_query.sh" \
        "${JOB_ID}/vertices/${VERTEX_ID}/subtasks/metrics" |
    jq -r '.[].id' |
    sort

    exit 0
fi

if [[ -z "$aggregations" ]]; then
    aggregations="sum,avg,min,max"
fi

JSON=$(
    bash "$DIR_BASE/get_query.sh" \
        "${JOB_ID}/vertices/${VERTEX_ID}/subtasks/metrics?get=${metrics}&agg=${aggregations}"
)

#
# Machine-readable mode.
#
if [[ "${RAW_OUTPUT:-false}" == "true" ]]; then
    echo "$JSON"
    exit 0
fi

#
# Human-readable mode.
#
IFS=',' read -ra AGGS <<< "$aggregations"

printf "%-60s" "Metric"

for agg in "${AGGS[@]}"; do
    printf " %-18s" "$agg"
done

printf "\n"

printf '%*s\n' \
    $((60 + 19 * ${#AGGS[@]})) \
    '' |
tr ' ' '-'

echo "$JSON" |
jq -c '.[]' |
while read -r row; do
    metric_id=$(echo "$row" | jq -r '.id')

    printf "%-60s" "$metric_id"

    for agg in "${AGGS[@]}"; do
        value=$(
            echo "$row" |
            jq -r \
                --arg agg "$agg" \
                '.[$agg] // "-"'
        )

        printf " %-18s" "$value"
    done

    printf "\n"
done