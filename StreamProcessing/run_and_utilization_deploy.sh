#!/bin/bash

n_nodes=$1
n_cores=$2
p_level=$3

make clean && make STREAM_PROCESSING N_NODES=${n_nodes} N_CORES=${n_cores} PARALLELISM_L=${p_level} -j && ./bin/STREAM_PROCESSING && python3 metrics/utilization_plot.py
