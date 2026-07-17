#!bin/bash


operator_name=$1
subtask_index=$2

bash get_query.sh $(bash get_job_id.sh)/vertices/$(bash get_oper_id.sh $operator_name)/subtasks/$subtask_index

