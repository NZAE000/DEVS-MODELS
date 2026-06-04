#!/bin/bash

# ============================================================
# Saturation experiment runner
# Reads all experiment parameters from a .cfg file
# ============================================================

CFG_FILE="experiments_cfg/saturation-experiment.cfg"

# ------------------------------------------------------------
# Check config file exists
# ------------------------------------------------------------
if [[ ! -f "$CFG_FILE" ]]; then
    echo "ERROR: Config file '$CFG_FILE' not found"
    exit 1
fi

# ------------------------------------------------------------
# Read config values
# ------------------------------------------------------------
APP=$(grep '^app:' "$CFG_FILE"    | cut -d':' -f2 | xargs)
NODES=$(grep '^nodes:' "$CFG_FILE" | cut -d':' -f2 | xargs)
CORES=$(grep '^cores:' "$CFG_FILE" | cut -d':' -f2 | xargs)
SLOTS=$(grep '^slots:' "$CFG_FILE" | cut -d':' -f2 | xargs)
REQS=$(grep '^reqs:' "$CFG_FILE"   | cut -d':' -f2 | xargs)
RATE=$(grep '^rate:' "$CFG_FILE"   | cut -d':' -f2 | xargs)
REPEATS=$(grep '^per_exec:' "$CFG_FILE"   | cut -d':' -f2 | xargs)
SLEEP_TIME=$(grep '^sleep:' "$CFG_FILE" | cut -d':' -f2 | xargs)

# Parse parallelism levels (comma-separated list)
P_LEVELS_RAW=$(grep '^p_levels:' "$CFG_FILE" | cut -d':' -f2)
IFS=',' read -ra PARALLEL_LEVELS <<< "$P_LEVELS_RAW"

# ------------------------------------------------------------
# Script execution
# ------------------------------------------------------------
SCRIPT="./execute_and_log_metrics.sh"

# ------------------------------------------------------------
# Print experiment summary
# ------------------------------------------------------------
echo "========================================"
echo " Saturation Experiment Configuration"
echo "========================================"
echo "Application      : $APP"
echo "Nodes            : $NODES"
echo "Cores per node   : $CORES"
echo "Taskslots        : $SLOTS"
echo "Requirements     : $REQS"
echo "Rate             : $RATE"
echo "Parallelism lvls : ${PARALLEL_LEVELS[*]}"
echo "Repeats per lvl  : $REPEATS"
echo "Sleep time (s)   : $SLEEP_TIME"
echo "========================================"
echo

# ------------------------------------------------------------
# Run experiment
# ------------------------------------------------------------
for P in "${PARALLEL_LEVELS[@]}"; do
    P=$(echo "$P" | xargs)  # trim spaces

    echo "----------------------------------------"
    echo "Parallelism level: $P"
    echo "----------------------------------------"

    for ((i=1; i<=REPEATS; i++)); do
        echo "[P=$P] Run $i / $REPEATS"

        bash "$SCRIPT" \
            "$APP" \
            "$NODES" \
            "$CORES" \
            "$SLOTS" \
            "$P" \
            "$REQS" \
            "$RATE"

        sleep "$SLEEP_TIME"
    done
done

echo "Saturation experiments done"
