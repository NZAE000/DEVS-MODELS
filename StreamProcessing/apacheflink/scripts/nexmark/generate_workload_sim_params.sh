#!/bin/bash

#==============================================================================
# Script to extract Nexmark's workload used and write them to input_data/workloadbyreq.txt
#==============================================================================

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

# Paths
CONFIG_FILE="$DIR_BASE/../../nexmark/conf/nexmark.yaml"
#OUTPUT_FILE="parameters/reqsRate.txt"
OUTPUT_FILE="$DIR_BASE/../../../input_data/workloadbyreq.txt"

#------------------------------------------------------------------------------
# Check if configuration file exists
#------------------------------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'."
  exit 1
fi

echo "[INFO] Generating workload from $CONFIG_FILE..."
#------------------------------------------------------------------------------
# Extract the number of events and tps fields
#------------------------------------------------------------------------------
events=$(grep -E "^nexmark\.workload\.suite\.100m\.events\.num:" "$CONFIG_FILE" | awk '{print $2}')
tps=$(grep -E "^nexmark\.workload\.suite\.100m\.tps:" "$CONFIG_FILE" | awk '{print $2}')

#------------------------------------------------------------------------------
# Validate extracted values
#------------------------------------------------------------------------------
if [ -z "$events" ]; then
  echo "Error: Field 'nexmark.workload.suite.100m.events.num' not found in configuration file."
  exit 1
fi

if [ -z "$tps" ]; then
  echo "Error: Field 'nexmark.workload.suite.100m.tps' not found in configuration file."
  exit 1
fi

#------------------------------------------------------------------------------
# Convert TPS to rate per picosecond
#------------------------------------------------------------------------------
rate_ns=$(awk -v tps="$tps" 'BEGIN {printf "%g", tps / 1e12}')

#------------------------------------------------------------------------------
# Ensure output directory exists
#------------------------------------------------------------------------------
mkdir -p "$(dirname "$OUTPUT_FILE")"

#------------------------------------------------------------------------------
# Write results to file
#------------------------------------------------------------------------------
echo "$events $rate_ns" > "$OUTPUT_FILE"

#------------------------------------------------------------------------------
# Confirmation message
#------------------------------------------------------------------------------
echo "[SUCCESS] Workload generated in '$OUTPUT_FILE':"
echo "  Events = $events"
echo "  Rate (per ns) = $rate_ns"

