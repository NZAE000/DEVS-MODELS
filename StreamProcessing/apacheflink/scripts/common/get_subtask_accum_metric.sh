#! bin/bash.sh

subtask_name=$1
metric=$2
accumulator=$3

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/get_query.sh $(bash $DIR_BASE/get_job_id.sh)/vertices/$(bash $DIR_BASE/get_subtask_id.sh $subtask_name)/subtasks/metrics?get=$metric | jq -r --arg f "$accumulator" '.[] | "\(.[$f])"'
