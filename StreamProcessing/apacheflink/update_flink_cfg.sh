#!/bin/bash

# ==========================================
# Updates the 'parallelism.default' value in
# the Flink configuration file (config.yaml)
#
# Usage: ./update_flink_cfg.sh <parallelism_level>
# Example: ./update_flink_cfg.sh 8
# ==========================================

# Check if a parameter was provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <taskslots_num> <parallelism_level>"
    exit 1
fi

# Read the input parameters
TASKSLOTS="$1"
PARALLELISM="$2"

# Path to the Flink configuration file
CONFIG_FILE="flink/conf/config.yaml"

# Check if the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: File not found - $CONFIG_FILE"
    exit 1
fi
:
# Check if the field 'parallelism.default' exists
if ! grep -q "^parallelism.default:" "$CONFIG_FILE"; then
    echo "Error: 'parallelism.default' field not found in $CONFIG_FILE"
    exit 1
fi
if ! grep -q "^taskmanager.numberOfTaskSlots:" "$CONFIG_FILE"; then
    echo "Error: 'taskmanager.numberOfTaskSlots' field not found in $CONFIG_FILE"
    exit 1
fi

# Update the 'parallelism.default' field
sed -i "s/^parallelism\.default:.*/parallelism.default: ${PARALLELISM}/" "$CONFIG_FILE"
# Update the 'taskmanager.numberOfTaskSlots' field
sed -i "s/^taskmanager\.numberOfTaskSlots:.*/taskmanager.numberOfTaskSlots: ${TASKSLOTS}/" "$CONFIG_FILE"

echo "Update configuration $CONFIG_FILE:"
echo "   'taskmanager.numberOfTaskSlots: ${TASKSLOTS}"
echo "   'parallelism.default: ${PARALLELISM}"
