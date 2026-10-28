#!/usr/bin/env bash
set -Eeuo pipefail

if [ $# -lt 7 ] || [ $# -gt 8 ]; then
    echo "Use: bash execute_and_gen_sim_params.sh <app> <app_dir> <taskslots> <parallelism> <events> <tps> <snapshot_interval_ms> <capacity|scalability>"
    exit 1
fi

app=$1
app_dir=$2
slots=$3
p=$4
req=$5
rate=$6
snap_interval=$7
mode=${8:-capacity}

if [ "$mode" != "capacity" ] && [ "$mode" != "scalability" ]; then
    echo "Error: mode must be 'capacity' or 'scalability'."
    exit 1
fi


## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/kill_java_process.sh
bash "$DIR_BASE/../${app_dir}/execute.sh" "$app" "$slots" "$p" "$req" "$rate" &
sleep 5

bash $DIR_BASE/collect_subtask_metrics_snapshot.sh $snap_interval
bash $DIR_BASE/extract_subtasks.sh && \
python3 $DIR_BASE/generate_metrics_intervals_from_snapshots.py $req $rate $mode

bash $DIR_BASE/generate_operator_sim_params.sh && \
bash $DIR_BASE/../${app_dir}/generate_workload_sim_params.sh