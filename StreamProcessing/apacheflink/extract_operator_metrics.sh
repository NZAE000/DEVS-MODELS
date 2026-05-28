#!/bin/bash

# ----------------------------------------------------------------------
# Exctract all operator metrics in 'metrics/opearor-name.txt' path with format f. ex:
# read-records;8000000
# write-records;8000000
# accumulateBusyTimeMs;2953.00000000000000000000
# mailboxLatencyMs_p95;0.0
# mailboxLatencyMs_p99;0.0
# mailboxLatencyMs_stddev;0.0
# ----------------------------------------------------------------------

JOB_ID=$(bash get_job_id.sh)
FLINK_URL="http://localhost:8081"
OPERLIST_DIR="operators/operators_list.txt"
METRICS_DIR="metrics"

if [ ! -f "${OPERLIST_DIR}" ]; then
  echo "[ERROR] ${OPERLIST_DIR} not found. Run first get_job_and_operators.sh"
  exit 1
fi

mkdir -p "$METRICS_DIR"
rm "$METRICS_DIR"/*

while IFS=';' read -r OPER_ID OPER_NAME PARALLELISM OPER_ID_NEXT SHIP_STRATEGY; do

  OUT_FILE="${METRICS_DIR}/${OPER_NAME}.txt"
  echo "[INFO] Processing ${OPER_NAME} (par=${PARALLELISM})"

  total_read=0
  total_write=0
  total_acum_busy=0.0

  for ((i=0; i<PARALLELISM; i++)); do

    JSON=$(curl -s "${FLINK_URL}/jobs/${JOB_ID}/vertices/${OPER_ID}/subtasks/${i}")
    read=$(echo "$JSON" | jq '.metrics["read-records"] // 0')
    write=$(echo "$JSON" | jq '.metrics["write-records"] // 0')
    busy=$(echo "$JSON" | jq '.metrics["accumulated-busy-time"] // 0')
    
    total_read=$(( total_read + read ))
    total_write=$(( total_write + write ))
    total_acum_busy=$(echo "$total_acum_busy + $busy" | bc -l)
  done

  # Store in file
  cat > "$OUT_FILE" <<EOF
read-records;$((total_read / PARALLELISM))
write-records;$((total_write / PARALLELISM))
accumulateBusyTimeMs;$(echo "$total_acum_busy / $PARALLELISM" | bc -l)
$(curl -s "${FLINK_URL}/jobs/${JOB_ID}/vertices/${OPER_ID}/subtasks/metrics?get=mailboxLatencyMs_p95,mailboxLatencyMs_p99,mailboxLatencyMs_stddev" \
  | jq -r --arg f "avg" '.[] | "\(.id);\(.[$f])"')
EOF

echo "Store in: ${OUT_FILE}"
done < "$OPERLIST_DIR"

echo "[SUCCESS] Metrics exported."
echo ""

