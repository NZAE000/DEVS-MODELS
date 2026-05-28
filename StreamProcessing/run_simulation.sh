#!/bin/bash

app=$1
n_nodes=$2
n_cores=$3
p_level=$4
n_exec=$5
registry=$6

make clean && make STREAM_PROCESSING N_NODES=${n_nodes} N_CORES=${n_cores} PARALLELISM_L=${p_level} -j

for E in $(seq 1 $n_exec); do
    ./bin/STREAM_PROCESSING ${app} ${registry}
done
