#!/usr/bin/env bash
set -Eeuo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <subtask_name> <subtask_index>" >&2
    exit 1
fi

subtask_name=$1
subtask_index=$2

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/get_query.sh $(bash $DIR_BASE/get_job_id.sh)/vertices/$(bash $DIR_BASE/get_subtask_id.sh $subtask_name)/subtasks/$subtask_index
