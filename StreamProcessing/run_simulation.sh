#!/usr/bin/env bash
set -Eeuo pipefail

if [ $# -ne 10 ]; then
    echo "Use: bash run_simulation.sh <app> <app_dir> <nodes> <cores> <p_level> <prod_mod> <n_exec> <apply_log> <log_mod> <print_log>"
    exit 1
fi

app=$1
app_dir=$2
n_nodes=$3
n_cores=$4
p_level=$5
prod_mod=$6
n_exec=$7
apply_log=$8
log_mod=$9
print_log=${10}

make clean && make STREAM_PROCESSING N_NODES=${n_nodes} N_CORES=${n_cores} PARALLELISM_L=${p_level} PROD_MOD=${prod_mod} APPLY_LOG=${apply_log} LOG_MOD=${log_mod} PRINT_LOG=${print_log} -j

for ((i=1; i<=n_exec; i++)); do
    echo "Run $i / $n_exec"
    ./bin/STREAM_PROCESSING ${app} ${app_dir}
done
