#!/bin/bash

#==============================================================================
# Script to extract Nexmark parameters and write them to parameters/reqsRate.txt
#==============================================================================

# Paths
CONFIG_FILE="nexmark/conf/nexmark.yaml"
#OUTPUT_FILE="parameters/reqsRate.txt"
OUTPUT_FILE="/mnt/c/Users/Cuda/Documents/eliezer/cadmium/DEVS-MODELS/StreamProcessing/input_data/reqsRate.txt"

#------------------------------------------------------------------------------
# Check if configuration file exists
#------------------------------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'."
  exit 1
fi

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
echo "Values written to '$OUTPUT_FILE':"
echo "  Events = $events"
echo "  Rate (per ns) = $rate_ns"

