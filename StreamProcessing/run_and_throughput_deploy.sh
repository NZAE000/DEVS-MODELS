#!/bin/bash

n_nodes=$1
n_cores=$2
p_level=$3
n_exec=$4
empty=$5
path="metrics/throughput_result.txt"

# If 1, empty file
if [ "$empty" -eq 1 ]; then
    > "$path"  # This empties the file.
fi

make clean && make STREAM_PROCESSING N_NODES=${n_nodes} N_CORES=${n_cores} PARALLELISM_L=${p_level} -j

for E in $(seq 1 $n_exec); do
    ./bin/STREAM_PROCESSING && python3 metrics/throughput_arrival_record.py
done

python3 metrics/throughput_arrival_plot.py
