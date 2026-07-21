#!bin/bash

opername=$1
subtask_index=$2

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/get_query.sh $(bash $DIR_BASE/get_job_id.sh)/vertices/$(bash $DIR_BASE/get_oper_id.sh $opername)/subtasks/$subtask_index

