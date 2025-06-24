#!/bin/bash

n_nodes=$1
n_cores=$2
n_exec=$3
empty=$4
path="metrics/throughput_result.txt"

# If 1, empty file
if [ "$empty" -eq 1 ]; then
    > "$path"  # Esto vacía el archivo
fi

make clean && make STREAM_PROCESSING N_NODES=${n_nodes} N_CORES=${n_cores} -j

for E in $(seq 1 $n_exec); do
    ./bin/STREAM_PROCESSING && python3 metrics/throughput_arrival_record.py
done

python3 metrics/throughput_arrival_plot.py
