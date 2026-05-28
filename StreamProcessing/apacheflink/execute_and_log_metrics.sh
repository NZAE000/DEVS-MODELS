#!/bin/bash

APP_NAME="$1"
NUM_MACHINES="$2"
NUM_CORES="$3"
TASKSLOTS="$4"
PARALLELISM="$5"
EVENTS="$6"
TPS="$7"

if [ $# -ne 6 ]; then
    echo "Uso: bash execute_and_log.sh <app> <n_machines> <cores> <taskslots> <parallelism> <events> <tps>"
    exit 1
fi

THROUGHPUT_ABSPATH="/mnt/c/Users/Cuda/Documents/eliezer/cadmium/DEVS-MODELS/StreamProcessing/metrics/nexmark/throughput/real"
UTILIZATION_ABSPATH="/mnt/c/Users/Cuda/Documents/eliezer/cadmium/DEVS-MODELS/StreamProcessing/metrics/nexmark/utilization/real"
THROUGHPUT_OUTFILE="${APP_NAME}-throughput-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}-${EVENTS}-${TPS}.txt"
UTILIZATION_OUTFILE="${APP_NAME}-utilization-${NUM_MACHINES}-${NUM_CORES}-${PARALLELISM}-${EVENTS}-${TPS}.txt"

# ============================
# Execute app
# ============================
bash execute.sh "$APP_NAME" "$TASKSLOTS" "$PARALLELISM" "$EVENTS" "$TPS"


# =======================================================
# Capture timestamps and calcule metrics when app finish
# =======================================================
FLINK_URL="http://localhost:8081"
JOB_ID=$(curl -s "${FLINK_URL}/jobs" | jq -r '.jobs[0].id')
if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
  echo "[ERROR] There are no active or completed jobs."
  exit 1
fi

start_time=$(curl -s "${FLINK_URL}/jobs/${JOB_ID}" | jq -r '.timestamps.RUNNING')
end_time=$(curl -s "${FLINK_URL}/jobs/${JOB_ID}" | jq -r '.timestamps.FINISHED')
finish_time_ms=$(echo "$end_time - $start_time" | bc -l)
FINISH_TIME=$(echo "$finish_time_ms / 1000" | bc -l)
THROUGHPUT=$(echo "$EVENTS / $FINISH_TIME" | bc -l)

# ============================
# Store f_time and throughbput
# ============================
printf "%.4f %.4f\n" "$FINISH_TIME" "$THROUGHPUT" >> "$THROUGHPUT_ABSPATH/$THROUGHPUT_OUTFILE"

# =======================================================
# Obtain metrics per operator to calculate utilization
# =======================================================
PLAN_JSON="plan_tmp.json"

# Get job with plan
curl -s "${FLINK_URL}/jobs/${JOB_ID}" > "$PLAN_JSON"

# ---------------------------------------------------------------------------------
# Extract data from .vertices[]  →  ID, name, parallelism TO CALCULATE UTILIZATION
# ---------------------------------------------------------------------------------
normalize() {
    echo "$1" | tr -d '_[]: ' | tr '[:upper:]' '[:lower:]'
}

TOTAL_ACUM_BUSY_TIME=0.0
#echo "Record added:"
#printf "%-25s %-15s %-15s %-15s %-15s\n" "Operator" "Parallelism" "AccumBusyTime" "BusyTime" "Utilization"
while IFS=';' read -r OPER_ID RAW_NAME PAR; do
    NAME=$(normalize "$RAW_NAME")
    total_acum_busy=0.0
    for ((i=0; i<PARALLELISM; i++)); do
        JSON=$(curl -s "${FLINK_URL}/jobs/${JOB_ID}/vertices/${OPER_ID}/subtasks/${i}") 
        busy=$(echo "$JSON" | jq '.metrics["accumulated-busy-time"] // 0')
        total_acum_busy=$(echo "$total_acum_busy + $busy" | bc -l)
    done
    ACUM_BUSY_TIME=$(echo "$total_acum_busy / 1000.0" | bc -l)  # To second.
    TOTAL_ACUM_BUSY_TIME=$(echo "$TOTAL_ACUM_BUSY_TIME + $ACUM_BUSY_TIME" | bc -l)
    BUSY_TIME=$(echo "$ACUM_BUSY_TIME / $PAR" | bc -l)          # Avg
    UTILIZATION=$(echo "($BUSY_TIME) / $FINISH_TIME" | bc -l)
    
    # Store in file.
    #printf "%-25s %-15s %-15.4f %-15.4f %-15s\n" "$NAME" "$PAR" "$ACUM_BUSY_TIME" "$BUSY_TIME" "$UTILIZATION"
    printf "%s:%s;" "$NAME" "$UTILIZATION" >> "$UTILIZATION_ABSPATH/$UTILIZATION_OUTFILE"

done < <(jq -r '.vertices[] | "\(.id);\(.name);\(.parallelism)"' "$PLAN_JSON")
printf "\n" >> "$UTILIZATION_ABSPATH/$UTILIZATION_OUTFILE"
#echo "Total time: $TOTAL_ACUM_BUSY_TIME" 

rm $PLAN_JSON

printf "\nRecords added: \n" # %.4f s %.4f req/s\n" "$FINISH_TIME" "$THROUGHPUT"
printf "\t$THROUGHPUT_ABSPATH/$THROUGHPUT_OUTFILE\n\t$UTILIZATION_ABSPATH/$UTILIZATION_OUTFILE\n"

