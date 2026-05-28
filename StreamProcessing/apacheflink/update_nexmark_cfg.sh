#!/bin/bash

# ============================================================
# Script to update 'events.num' y 'tps' values
# in nexmark/conf/nexmark.yaml configuration.
# Use:
#   ./update_nexmark_config.sh <num_eventos> <tps>
# Example:
#   ./update_nexmark_config.sh 2000000 8000
# ============================================================

# Check params
if [ $# -ne 2 ]; then
  echo "Use: $0 <num_eventos> <tps>"
  exit 1
fi

EVENTS_NUM=$1
TPS=$2
CONFIG_FILE="nexmark/conf/nexmark.yaml"

# Check file configuration
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: file not found '$CONFIG_FILE'"
  exit 1
fi

# Using sed adn regular expressions to update lines 
sed -i "s/^\(nexmark\.workload\.suite\.100m\.events\.num:\).*/\1 ${EVENTS_NUM}/" "$CONFIG_FILE"
sed -i "s/^\(nexmark\.workload\.suite\.100m\.tps:\).*/\1 ${TPS}/" "$CONFIG_FILE"

echo "Update configuration $CONFIG_FILE:"
echo "   nexmark.workload.suite.100m.events.num: ${EVENTS_NUM}"
echo "   nexmark.workload.suite.100m.tps: ${TPS}"

