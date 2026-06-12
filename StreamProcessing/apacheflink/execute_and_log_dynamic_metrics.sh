#!/bin/bash

APP_NAME="$1"
NUM_MACHINES="$2"
NUM_CORES="$3"
TASKSLOTS="$4"
PARALLELISM="$5"
EVENTS="$6"
TPS="$7"

if [ $# -ne 7 ]; then
    echo "Use: bash execute_and_log_dynamic_metrics.sh <app> <n_machines> <cores> <taskslots> <parallelism> <events> <tps>"
    exit 1
fi

THROUGHPUT_PATH="../metrics/nexmark/throughput/real/dynamic"
UTILIZATION_PATH="../metrics/nexmark/utilization/real/dynamic"
CPU_UTIL_PATH="../metrics/nexmark/cpu_util/real/dynamic"

mkdir -p "$THROUGHPUT_PATH"
mkdir -p "$UTILIZATION_PATH"
mkdir -p "$CPU_UTIL_PATH"

THROUGHPUT_OUTFILE="$THROUGHPUT_PATH/dynamic-throughput-real-${APP_NAME}-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}.txt"
UTILIZATION_OUTFILE="$UTILIZATION_PATH/dynamic-utilization-real-${APP_NAME}-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}.txt"
CPU_UTIL_OUTFILE="$CPU_UTIL_PATH/dynamic-cpu-real-${APP_NAME}-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}.txt"
CPU_LOG="/tmp/cpu_${APP_NAME}_${TASKSLOTS}_${PARALLELISM}_${EVENTS}_${TPS}.log"

########################################################
# Init files
########################################################
echo -n "${TPS}:" > "$THROUGHPUT_OUTFILE"
echo -n "${TPS}:" > "$CPU_UTIL_OUTFILE"
echo "${TPS}" > "$UTILIZATION_OUTFILE"

########################################################
# Structures in memory
########################################################
declare -a THROUGHPUT_LIST
declare -a CPU_UTIL_LIST
declare -A UTILIZATION_MAP
declare -A ACCUM_BUSY_MAP
CURRENT_REQS=-1

########################################################
# Config
########################################################
bash update_flink_cfg.sh "$TASKSLOTS" "$PARALLELISM"
bash update_nexmark_cfg.sh "$EVENTS" "$TPS"

########################################################
# Reset cluster
########################################################
bash stop.sh
bash start.sh

########################################################
# execute query in background
########################################################
bash run-query.sh "$APP_NAME" &
QUERY_PID=$!

########################################################
# Wait job creation
########################################################
JOB_ID=""
while true
do
    JOB_ID=$(bash get_job_id.sh)
    if [[ "$JOB_ID" != "" && "$JOB_ID" != "null" ]]; then
        break
    fi
    sleep 1
done

########################################################
# Wait RUNNING state
########################################################
while true
do
    STATE=$(bash get_query.sh $(bash get_job_id.sh) | jq -r '.state')
    echo "State: $STATE"
    if [[ "$STATE" == "RUNNING" ]]; then
        break
    fi
done

sleep 1
########################################################
# Get operator names
########################################################
mapfile -t OPERATORS < <(bash get_operator_names.sh)
for op in "${OPERATORS[@]}"
do
    UTILIZATION_MAP["$op"]=""
    ACCUM_BUSY_MAP["$op"]=""
done

########################################################
# Main loop
########################################################
while true
do
    #start=$(date +%s.%N) # Begin time point

    STATE=$(bash get_query.sh "$JOB_ID" | jq -r '.state')
    if [[ "$STATE" == "FINISHED" ]]; then
        break
    fi

    ####################################################
    # Accumulated time
    ####################################################
    ACCUM_TIME_MS=$(bash get_query.sh "$JOB_ID" | jq -r '.duration')
    ACCUM_TIME=$(echo "scale=6; $ACCUM_TIME_MS / 1000.0" | bc -l)
    
    ####################################################
    # Total requeriments
    ####################################################
    total_req=0
    for ((i=0;i<PARALLELISM;i++))
    do
        req=$(bash get_suboperator_metrics.sh source "$i" | jq '.metrics["write-records"] // 0')
        total_req=$((total_req + req))
    done

    ####################################################
    # Throughput: calculate if reqs change
    ####################################################
    if [[ "$CURRENT_REQS" != "$total_req" ]]; then
        CURRENT_REQS=$total_req #Update

        THROUGHPUT=$(echo "scale=6; $total_req / $ACCUM_TIME" | bc -l)
        THROUGHPUT_LIST+=("${ACCUM_TIME},${THROUGHPUT}")
    fi

    ####################################################
    # Operator Utilizations: calculate if accumbusy change
    ####################################################
    for opername in "${OPERATORS[@]}"
    do
        id_op=$(bash get_oper_id.sh "$opername")
        total_acum_busy=0

        for ((i=0;i<PARALLELISM;i++))
        do
            METRICS=$(bash get_suboperator_metrics.sh "$id_op" "$i")
            busy=$(echo "$METRICS" | jq '.metrics["accumulated-busy-time"] // 0')
            total_acum_busy=$(echo "$total_acum_busy + $busy" | bc -l)
        done

        if [[ "${ACCUM_BUSY_MAP["$opername"]}" != "$total_acum_busy"  ]]; then
            ACCUM_BUSY_MAP["$opername"]="$total_acum_busy" # Update

            ACUM_BUSY_TIME=$(echo "$total_acum_busy / 1000.0" | bc -l)
            BUSY_TIME=$(echo "$ACUM_BUSY_TIME / $PARALLELISM" | bc -l)
            UTILIZATION=$(echo "scale=8; $BUSY_TIME / $ACCUM_TIME" | bc -l)
            UTILIZATION_MAP["$opername"]+="${UTILIZATION} "
        fi
    done

    ####################################################
    # CPU Utilization
    ####################################################
    mpstat -P ALL > "$CPU_LOG"
    cpu_sum=0
    cpu_count=0

    while read -r line
    do
        cpu=$(echo "$line" | awk '{print $2}')
        if [[ "$cpu" =~ ^[0-9]+$ ]]; then

            idle=$(echo "$line" | awk '{print $NF}')
            util=$(echo "100 - $idle" | bc -l)
            cpu_sum=$(echo "$cpu_sum + $util" | bc -l)
            cpu_count=$((cpu_count + 1))
        fi

    done < "$CPU_LOG"

    CPU_UTIL=$(echo "scale=6; $cpu_sum / $cpu_count" | bc -l)
    CPU_UTIL_LIST+=("${ACCUM_TIME},${CPU_UTIL}")
    ####################################################

    #end=$(date +%s.%N) # End time ponit
    #elapsed=$(echo "$end - $start" | bc -l) # Elapsed time
    #wait=$(echo "1.0 - $elapsed" | bc -l)
#
    #if (( $(echo "$wait > 0" | bc -l) )); then
    #    sleep "$wait"
    #fi
done

########################################################
# Wait for the process to finish
########################################################
wait $QUERY_PID

########################################################
# Write throughput
########################################################
printf "%s " "${THROUGHPUT_LIST[@]}" >> "$THROUGHPUT_OUTFILE"
echo "" >> "$THROUGHPUT_OUTFILE"

########################################################
# Write CPU
########################################################
printf "%s " "${CPU_UTIL_LIST[@]}" >> "$CPU_UTIL_OUTFILE"
echo "" >> "$CPU_UTIL_OUTFILE"

########################################################
# Write utilizacions
########################################################
for op in "${OPERATORS[@]}"
do
    echo "${op}:[${UTILIZATION_MAP[$op]}]" >> "$UTILIZATION_OUTFILE"
done

echo "Dynamic metrics successfully. Written to:"
echo "'$THROUGHPUT_OUTFILE'"
echo "'$UTILIZATION_OUTFILE'"
echo "'$CPU_UTIL_OUTFILE'"
