#!/bin/bash

operator="$1"
replic="$2"

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

for ((index=0; index<=replic; index++)); do
    bash $DIR_BASE/get_busytime_operators.sh "$index" | awk -v op="$operator" '$0 ~ op {getline; print $2}'
done
