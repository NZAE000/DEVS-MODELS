#!/bin/bash

# ============================================================
# Without-saturation experiment runner
# Sweeps multiple (reqs, rate) load pairs and parallelism levels
# All parameters are read from a .cfg file
# ============================================================

CFG_FILE="experiments_cfg/without-saturation-experiment.cfg"

# ------------------------------------------------------------
# Check config file exists
# ------------------------------------------------------------
if [[ ! -f "$CFG_FILE" ]]; then
    echo "ERROR: Config file '$CFG_FILE' not found"
    exit 1
fi

# ------------------------------------------------------------
# Read basic configuration values
# ------------------------------------------------------------
APP=$(grep '^app:' "$CFG_FILE"     | cut -d':' -f2 | xargs)
NODES=$(grep '^nodes:' "$CFG_FILE" | cut -d':' -f2 | xargs)
CORES=$(grep '^cores:' "$CFG_FILE" | cut -d':' -f2 | xargs)
PER_EXEC=$(grep '^per_exec:' "$CFG_FILE" | cut -d':' -f2 | xargs)
SLEEP_TIME=$(grep '^sleep:' "$CFG_FILE" | cut -d':' -f2 | xargs)

# ------------------------------------------------------------
# Parse loads: reqs-rate pairs
# ------------------------------------------------------------
LOADS_RAW=$(grep '^loads:' "$CFG_FILE" | cut -d':' -f2)
IFS=',' read -ra LOADS <<< "$LOADS_RAW"

# ------------------------------------------------------------
# Parse parallelism levels
# ------------------------------------------------------------
P_LEVELS_RAW=$(grep '^p_levels:' "$CFG_FILE" | cut -d':' -f2)
IFS=',' read -ra PARALLEL_LEVELS <<< "$P_LEVELS_RAW"

# ------------------------------------------------------------
# Experiment command
# ------------------------------------------------------------
SCRIPT="./execute_and_log_metrics.sh"

# ------------------------------------------------------------
# Print experiment summary
# ------------------------------------------------------------
echo "========================================"
echo " Without-Saturation Experiment Config"
echo "========================================"
echo "Application        : $APP"
echo "Nodes              : $NODES"
echo "Cores per node     : $CORES"
echo "Loads (reqs-rate)  : ${LOADS[*]}"
echo "Parallelism levels : ${PARALLEL_LEVELS[*]}"
echo "Runs per config    : $PER_EXEC"
echo "Sleep time (s)     : $SLEEP_TIME"
echo "========================================"
echo

# ------------------------------------------------------------
# Run experiment
# ------------------------------------------------------------
for LOAD in "${LOADS[@]}"; do
    LOAD=$(echo "$LOAD" | xargs)  # trim spaces

    REQS=${LOAD%%-*}
    RATE=${LOAD##*-}

    echo "----------------------------------------"
    echo "Load: reqs=$REQS | rate=$RATE"
    echo "----------------------------------------"

    for P in "${PARALLEL_LEVELS[@]}"; do
        P=$(echo "$P" | xargs)

        echo "  Parallelism level: $P"

        for ((i=1; i<=PER_EXEC; i++)); do
            echo "  Run $i / $PER_EXEC"

            bash "$SCRIPT" \
                "$APP" \
                "$NODES" \
                "$CORES" \
                "$P" \
                "$REQS" \
                "$RATE"

            sleep "$SLEEP_TIME"
        done
    done
done

echo "Without-saturation experiments done"
