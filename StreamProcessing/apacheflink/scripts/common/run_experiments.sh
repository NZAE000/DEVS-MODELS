#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Experiment runner
# Sweeps multiple (reqs, rate) load pairs and parallelism levels
# All parameters are read from a .cfg file
# ============================================================

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

CFG_FILE="$DIR_BASE/../../experiments_cfg/experiment.cfg"

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
APP_DIR=$(grep '^app_dir:' "$CFG_FILE"     | cut -d':' -f2 | xargs)
SLOTS=$(grep '^slots:' "$CFG_FILE" | cut -d':' -f2 | xargs)
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
# Print experiment summary
# ------------------------------------------------------------
echo "========================================"
echo " Experiment Config"
echo "========================================"
echo "Application        : $APP"
echo "App directory      : $APP_DIR"
echo "Taskslots          : $SLOTS"
echo "Loads (reqs-rate)  : ${LOADS[*]}"
echo "Parallelism levels : ${PARALLEL_LEVELS[*]}"
echo "Runs per config    : $PER_EXEC"
echo "Sleep time (s)     : $SLEEP_TIME"
echo "========================================"
echo

# ------------------------------------------------------------
# Experiment command
# ------------------------------------------------------------
SCRIPT="$DIR_BASE/../${APP_DIR}/execute.sh"

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
                "$SLOTS" \
                "$P" \
                "$REQS" \
                "$RATE"

            sleep "$SLEEP_TIME"
        done
    done
done

echo "Experiments done"
