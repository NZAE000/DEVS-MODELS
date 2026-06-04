#!/bin/bash

app=$1
n_nodes=$2
n_cores=$3
p_level=$4
prod_mod=$5
n_exec=$6
apply_log=$7
log_mod=$8

make clean && make STREAM_PROCESSING N_NODES=${n_nodes} N_CORES=${n_cores} PARALLELISM_L=${p_level} PROD_MOD=${prod_mod} APPLY_LOG=${apply_log} LOG_MOD=${log_mod} -j

for E in $(seq 1 $n_exec); do
    ./bin/STREAM_PROCESSING ${app}
done
