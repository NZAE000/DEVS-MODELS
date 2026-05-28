#!bin/bash


subtask_index=$1
for O in $(cat operators/operators_list.txt | cut -d';' -f 2); do echo $O; bash get_suboperator_metrics.sh $O $subtask_index | grep "accumulated-busy-time"; done
