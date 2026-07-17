#!/bin/bash

operator="$1"
replic="$2"

for ((index=0; index<=replic; index++)); do
    bash get_busytime_operators.sh "$index" | awk -v op="$operator" '$0 ~ op {getline; print $2}'
done
