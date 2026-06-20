#!/bin/bash

CONFIG_FILE="scalability-experiments.cfg"

# Check if the file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: don't exist $CONFIG_FILE"
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
        workload)   WORKLOAD="$value" ;;
        p_levels)   P_LEVELS="$value" ;;
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
echo "Workload    : $WORKLOAD"
echo "Prod Mod    : $PROD_MOD"
echo "Per Exec    : $PER_EXEC"
echo "Log         : $LOG"
echo "Log mod     : $LOG_MOD"
echo "Print Log   : $PRINT_LOG"
echo "======================================="

# Separate workload by req and rate
WORKLOAD=$(echo "$WORKLOAD" | xargs)
REQS=$(echo "$WORKLOAD" | cut -d'-' -f1)
RATE=$(echo "$WORKLOAD" | cut -d'-' -f2)

# Separe p levels by coma
IFS=',' read -ra PL_ARRAY <<< "$P_LEVELS"


# Before, execute real app and generate simulation parameters
#(
#    cd apacheflink || exit 1
#    bash execute_and_gen_sim_params.sh \
#        "$APP" \
#        "$SLOTS" \
#        "1" \
#        "$REQS" \
#        "$RATE"
#)

for pl in "${PL_ARRAY[@]}"; do
    pl=$(echo "$pl" | xargs)  # trim spaces
    echo
    echo "======================================="
    echo "P level: $pl"
    echo "======================================="

    (
        cd apacheflink || exit 1
        bash  move_degrad_and_occup_factors_to_sim_param.sh \
            "$APP" \
            "$pl" 
    )

    # Execute simulation
    bash run_simulation.sh \
        "$APP" \
        "$NODES" \
        "$CORES" \
        "$pl" \
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
echo "Scalability experiments finished."