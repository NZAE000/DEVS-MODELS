#! bin/bash.sh
APP_NAME="$1"
TASKSLOTS="$2"
PARALLELISM="$3"
EVENTS="$4"
TPS="$5"

CPU_LOG="/tmp/cpu_${APP_NAME}_${TASKSLOTS}_${PARALLELISM}_${EVENTS}_${TPS}.log"

# ============================
# Update flink parameters
# ============================
bash update_flink_cfg.sh $TASKSLOTS $PARALLELISM && bash update_nexmark_cfg.sh $EVENTS $TPS

# ============================
# Stop and init
# ============================
bash stop.sh && bash start.sh

# =======================================
# Start CPU monitoring while app execute
# =======================================
mpstat -P ALL 1 > "$CPU_LOG" &
MPSTAT_PID=$!

# ============================
# Execute app
# ============================
bash run-query.sh $APP_NAME

# ================================
# Kill monitorign when app finish
# ================================
kill $MPSTAT_PID

# ================================
# Calculate avg CPU utilization
# ================================
CPU_UTIL=$(awk '
  $2 == "all" {
    idle += $NF
    n++
  }
  END {
    if (n > 0) printf "%.4f", ((100 - (idle / n)) / 100)
    else print "0.0"
  }
' "$CPU_LOG")


rm $CPU_LOG # Delete temp
#echo "$CPU_UTIL"

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

# =============================================
# Show f_time, throughbput and cpu utilization
# =============================================
#printf "%.4f %.4f\n" "$FINISH_TIME" "$THROUGHPUT" >> "$THROUGHPUT_ABSPATH/$THROUGHPUT_OUTFILE"
printf "FTime: %.4f s, Throughput: %.4f req/s, CPUU: %.4f\n" "$FINISH_TIME" "$THROUGHPUT" "$CPU_UTIL"

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
echo ""
printf "%-25s %-5s %-15s %-15s %-15s\n" "Operator" "P" "AccumBusyTime" "BusyTime" "Utilization"
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
    
    printf "%-25s %-5s %-15.4f %-15.4f %-15s\n" "$NAME" "$PAR" "$ACUM_BUSY_TIME" "$BUSY_TIME" "$UTILIZATION"

done < <(jq -r '.vertices[] | "\(.id);\(.name);\(.parallelism)"' "$PLAN_JSON")

rm $PLAN_JSON
