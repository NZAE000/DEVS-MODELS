#! bin/bash.sh

app=$1
slots=$2
p=$3
req=$4
rate=$5
snap_interval=$6

if [ $# -ne 6 ]; then
    echo "Use: bash execute_and_gen_sim_params.sh <app> <taskslots> <parallelism> <events> <tps> <snapshot_interval_ms>"
    exit 1
fi

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

$(bash $DIR_BASE/execute.sh $app $slots $p $req $rate) & 
sleep 5
bash $DIR_BASE/../common/collect_subtask_metrics_snapshot.sh $snap_interval
bash $DIR_BASE/../common/extract_subtasks.sh && python3 $DIR_BASE/../common/generate_metrics_intervals_from_snapshots.py $req $rate
bash $DIR_BASE/../common/generate_operator_sim_params.sh && bash $DIR_BASE/generate_workload_sim_params.sh
