#!/bin/bash

CONFIG_FILE="capacity-experiments.cfg"

# Check if the file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: no existe $CONFIG_FILE"
    exit 1
fi

# Read cgf
while IFS=':' read -r key value; do
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)

    # Ignore comments
    [[ -z "$key" ]] && continue
    [[ "$key" =~ ^# ]] && continue

    case "$key" in
        app)        APP="$value" ;;
        nodes)      NODES="$value" ;;
        cores)      CORES="$value" ;;
        slots)      SLOTS="$value" ;;
        workloads)  WORKLOADS="$value" ;;
        p_level)    P_LEVEL="$value" ;;
        prod_mod)   PROD_MOD="$value" ;;
        per_exec)   PER_EXEC="$value" ;;
        log)        LOG="$value" ;;
        log_mod)    LOG_MOD="$value" ;;
        print_log)  PRINT_LOG="$value" ;;
    esac
done < "$CONFIG_FILE"

echo "======================================="
echo "Application : $APP"
echo "Nodes       : $NODES"
echo "Cores       : $CORES"
echo "Slots       : $SLOTS"
echo "P-Level     : $P_LEVEL"
echo "Prod Mod    : $PROD_MOD"
echo "Per Exec    : $PER_EXEC"
echo "Log         : $LOG"
echo "Log mod     : $LOG_MOD"
echo "Print Log   : $PRINT_LOG"
echo "======================================="

# Separe workloads by coma
IFS=',' read -ra WL_ARRAY <<< "$WORKLOADS"

for wl in "${WL_ARRAY[@]}"; do

    wl=$(echo "$wl" | xargs)

    REQS=$(echo "$wl" | cut -d'-' -f1)
    RATE=$(echo "$wl" | cut -d'-' -f2)

    echo
    echo "======================================="
    echo "Workload: reqs=$REQS rate=$RATE"
    echo "======================================="

    # Execute real app and generate simulation parameters
    (
        cd apacheflink || exit 1
        bash execute_and_gen_sim_params.sh \
            "$APP" \
            "$SLOTS" \
            "$P_LEVEL" \
            "$REQS" \
            "$RATE"
    )

    if [[ $? -ne 0 ]]; then
        echo "Error running Apache Flink for workload $wl"
        continue
    fi

    # Execute simulation
    bash run_simulation.sh \
        "$APP" \
        "$NODES" \
        "$CORES" \
        "$P_LEVEL" \
        "$PROD_MOD" \
        "$PER_EXEC" \
        "$LOG" \
        "$LOG_MOD"\
        "$PRINT_LOG"

    if [[ $? -ne 0 ]]; then
        echo "Error running simulation for workload $wl"
        continue
    fi

done

echo
echo "Capacity experiments finished."