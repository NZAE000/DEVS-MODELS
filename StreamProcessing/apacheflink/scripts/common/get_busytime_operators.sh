#!bin/bash

subtask_index=$1

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

for O in $(cat $DIR_BASE/../../operators/operator_list.txt | cut -d';' -f 2); do echo $O; bash $DIR_BASE/get_suboperator_metrics.sh $O $subtask_index | grep "accumulated-busy-time"; done
