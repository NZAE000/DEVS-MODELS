#!/bin/bash

#==============================================================================
# Script to extract Yahoo's workload used and write them to input_data/workloadbyrate.txt
#==============================================================================

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

# Paths
CONFIG_FILE="$DIR_BASE/../../yahoo/conf/workloadbyrate.txt"
#OUTPUT_FILE="parameters/reqsRate.txt"
OUTPUT_FILE="$DIR_BASE/../../../input_data/workloadbyreq.txt"

