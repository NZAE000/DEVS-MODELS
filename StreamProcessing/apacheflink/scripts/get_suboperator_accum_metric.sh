#! bin/bash.sh

opername=$1
metric=$2
accumulator=$3

bash get_query.sh $(bash get_job_id.sh)/vertices/$(bash get_oper_id.sh $opername)/subtasks/metrics?get=$metric | jq -r --arg f "$accumulator" '.[] | "\(.[$f])"'
