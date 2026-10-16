#!/usr/bin/env bash
set -Eeuo pipefail

subtask_name=${1:-}

DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

if [[ -z "$subtask_name" ]]; then
    echo "Usage: $0 <subtask_name>" >&2
    exit 1
fi

JOB_ID="${JOB_ID_OVERRIDE:-$(bash "$DIR_BASE/get_job_id.sh")}"

bash "$DIR_BASE/get_query.sh" "$JOB_ID" |
jq -r '.vertices[] | "\(.id);\(.name);"' |
tr -d '_[]: ' |
tr '[:upper:]' '[:lower:]' |
grep "$subtask_name" |
head -n 1 |
cut -d';' -f1