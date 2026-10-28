#!/usr/bin/env bash
set -Eeuo pipefail

#==============================================================================
# Script to extract Yahoo's workloads and write them to input_data/workloadbyreq.txt
#==============================================================================

DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

# Paths
CONFIG_FILE="$DIR_BASE/../../yahoo-ads/conf/workloadbyreq.txt"
OUTPUT_FILE="$DIR_BASE/../../../input_data/workloadbyreq.txt"

#------------------------------------------------------------------------------
# Check if configuration file exists
#------------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found at '$CONFIG_FILE'."
    exit 1
fi

echo "[INFO] Generating workload from $CONFIG_FILE..."

#------------------------------------------------------------------------------
# Ensure output directory exists
#------------------------------------------------------------------------------
mkdir -p "$(dirname "$OUTPUT_FILE")"

#------------------------------------------------------------------------------
# Convert all workloads
#
# Input:
#   events tps
#
# Output:
#   events rate_per_picosecond
#
# Empty lines and comments are ignored.
#------------------------------------------------------------------------------
awk '
BEGIN {
    count = 0
}

{
    sub(/#.*/, "", $0)
}

NF == 0 {
    next
}

NF < 2 {
    printf "Error: Invalid workload at line %d: expected <events> <tps>\n", NR > "/dev/stderr"
    exit 1
}

$1 !~ /^[0-9]+$/ {
    printf "Error: Invalid event count at line %d: %s\n", NR, $1 > "/dev/stderr"
    exit 1
}

$2 !~ /^[0-9]+([.][0-9]+)?$/ {
    printf "Error: Invalid TPS at line %d: %s\n", NR, $2 > "/dev/stderr"
    exit 1
}

{
    events = $1
    tps = $2
    rate_ps = tps / 1e12

    printf "%s %.12g\n", events, rate_ps
    count++
}

END {
    if (count == 0) {
        print "Error: No valid workloads were found." > "/dev/stderr"
        exit 1
    }
}
' "$CONFIG_FILE" > "$OUTPUT_FILE"

#------------------------------------------------------------------------------
# Confirmation message
#------------------------------------------------------------------------------
echo "[SUCCESS] Workload generated in '$OUTPUT_FILE':"
cat "$OUTPUT_FILE"