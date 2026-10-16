#!/bin/bash

# -------------------------
# Config file as argument
# -------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 load-sweep/nexmark/cfg/load-sweep-app.cfg"
    exit 1
fi

CFG=$1

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

# -------------------------
# Parse app name
# -------------------------
CFG_FILENAME="$(basename -- "$CFG")"
APP="${CFG_FILENAME##*-}"
APP="${APP%.cfg}"
echo "$APP"

# -------------------------
# Validate config file
# -------------------------
CFG="$DIR_BASE/../../load-sweep/nexmark/cfg/load-sweep-${APP}.cfg"

if [[ ! -f "$CFG" ]]; then
    echo "Error: configuration file does not exist: $CFG" >&2
    exit 1
fi

# -------------------------
# Output file name
# -------------------------
OUT="$DIR_BASE/../../load-sweep/nexmark/sweeps/load-sweep-${APP}.txt"
OUT_UTIL="$DIR_BASE/../../load-sweep/nexmark/sweeps/load-sweep-util-${APP}.txt"

# -------------------------
# Parse config
# -------------------------
N_SLOTS=$(grep '^slots:' "$CFG" | cut -d':' -f2 | xargs)
LOADS_RAW=$(awk -F': ' '/^loads:/ {print $2}' "$CFG")
P_RAW=$(awk -F': ' '/^p_levels:/ {print $2}' "$CFG")
N_RUNS=$(awk -F': ' '/^per_exec:/ {print $2}' "$CFG")

# Convert to arrays.
IFS=',' read -ra LOADS <<< "$LOADS_RAW"
IFS=',' read -ra P_LEVELS <<< "$P_RAW"

# Trim spaces.
for i in "${!LOADS[@]}"; do
    LOADS[$i]=$(echo "${LOADS[$i]}" | xargs)
done

for i in "${!P_LEVELS[@]}"; do
    P_LEVELS[$i]=$(echo "${P_LEVELS[$i]}" | xargs)
done

# -------------------------
# Write header
# -------------------------
{
    printf "parallelism"
    for L in "${LOADS[@]}"; do
        printf " %s" "$L"
    done
    printf "\n"
} >> "$OUT"

{
    printf "parallelism"
    for L in "${LOADS[@]}"; do
        printf " %s" "$L"
    done
    printf "\n"
} >> "$OUT_UTIL"

# -------------------------
# Main sweep
# -------------------------
for P in "${P_LEVELS[@]}"; do
    printf "%d" "$P" >> "$OUT"
    printf "%d" "$P" >> "$OUT_UTIL"

    printf "P=%d\n" "$P"

    for L in "${LOADS[@]}"; do
        printf "\t%s: " "$L"

        EVENTS=${L%-*}
        TPS=${L#*-}

        sum_ft=0
        sum_tp=0
        sum_cpu=0
        ok_runs=0

        declare -a op_names
        declare -A op_seen
        declare -A sum_in_records
        declare -A sum_out_records
        declare -A sum_busy
        declare -A sum_util
        declare -A count_op

        op_names=()
        op_seen=()
        sum_in_records=()
        sum_out_records=()
        sum_busy=()
        sum_util=()
        count_op=()

        for ((r=1; r<=N_RUNS; r++)); do
            TMP_OUT="/tmp/run_${APP}_${P}_${EVENTS}_${TPS}_$r.log"

            bash "$DIR_BASE/execute.sh" "$APP" "$N_SLOTS" "$P" "$EVENTS" "$TPS" > "$TMP_OUT" 2>&1

            # -------------------------
            # EXTRACT TIME, THROUGHPUT AND CPU
            # -------------------------
            RESULT=$(grep "^FTime:" "$TMP_OUT" | tail -n 1)

            if [ -z "$RESULT" ]; then
                echo "WARNING: missing FTime (P=$P, L=$L, run=$r)" >&2
                rm -f "$TMP_OUT"
                continue
            fi

            FT=$(echo "$RESULT" | cut -d',' -f1 | cut -d' ' -f2)
            TP=$(echo "$RESULT" | cut -d',' -f2 | cut -d' ' -f3)
            CPU=$(echo "$RESULT" | cut -d',' -f3 | cut -d' ' -f3)

            sum_ft=$(echo "$sum_ft + $FT" | bc -l)
            sum_tp=$(echo "$sum_tp + $TP" | bc -l)
            sum_cpu=$(echo "$sum_cpu + $CPU" | bc -l)
            ok_runs=$((ok_runs + 1))

            # --------------------------------------------------------------
            # EXTRACT OPERATOR METRICS
            #
            # execute.sh format:
            #
            #   Operator P InRecords OutRecords AccumBusyTime BusyTime Utilization
            #
            # Stored metrics:
            #
            #   InRecords
            #   OutRecords
            #   BusyTime      -> accumBusy
            #   Utilization
            # --------------------------------------------------------------
            UTIL_BLOCK=$(awk '
                /^Operator/ {flag=1; next}
                flag && NF==0 {flag=0}
                flag
            ' "$TMP_OUT")

            while read -r op par in_records out_records select accum_busy busy_time util rest; do
                if [[ -z "$op" || ! "$par" =~ ^[0-9]+$ ]]; then
                    continue
                fi

                if [[ -z "${op_seen[$op]+x}" ]]; then
                    op_seen["$op"]=1
                    op_names+=("$op")
                    sum_in_records["$op"]=0
                    sum_out_records["$op"]=0
                    sum_busy["$op"]=0
                    sum_util["$op"]=0
                    count_op["$op"]=0
                fi

                sum_in_records["$op"]=$(echo "${sum_in_records[$op]} + $in_records" | bc -l)
                sum_out_records["$op"]=$(echo "${sum_out_records[$op]} + $out_records" | bc -l)
                sum_busy["$op"]=$(echo "${sum_busy[$op]} + $busy_time" | bc -l)
                sum_util["$op"]=$(echo "${sum_util[$op]} + $util" | bc -l)
                count_op["$op"]=$(( ${count_op[$op]} + 1 ))
            done <<< "$UTIL_BLOCK"

            rm -f "$TMP_OUT"
            sleep 7
        done

        # -------------------------
        # GLOBAL AVERAGES
        # -------------------------
        if [ "$ok_runs" -gt 0 ]; then
            avg_ft=$(echo "$sum_ft / $ok_runs" | bc -l)
            avg_tp=$(echo "$sum_tp / $ok_runs" | bc -l)
            avg_cpu=$(echo "$sum_cpu / $ok_runs" | bc -l)
        else
            avg_ft="NaN"
            avg_tp="NaN"
            avg_cpu="NaN"
        fi

        printf " %.4f:%.4f:%.4f" "$avg_ft" "$avg_tp" "$avg_cpu" >> "$OUT"
        printf "%.4f:%.4f:%.4f\n" "$avg_ft" "$avg_tp" "$avg_cpu"

        # -------------------------
        # OPERATOR AVERAGES
        #
        # Output format:
        #
        #   operator:inRecords-outRecords-busyTime-utilization
        # -------------------------
        OP_METRICS_STR=""

        for op in "${op_names[@]}"; do
            count="${count_op[$op]}"

            if [ "$count" -le 0 ]; then
                continue
            fi

            avg_in_records=$(echo "${sum_in_records[$op]} / $count" | bc -l)
            avg_out_records=$(echo "${sum_out_records[$op]} / $count" | bc -l)
            avg_busy=$(echo "${sum_busy[$op]} / $count" | bc -l)
            avg_util=$(echo "${sum_util[$op]} / $count" | bc -l)

            OP_ENTRY="${op}:${avg_in_records}-${avg_out_records}-${avg_busy}-${avg_util}"

            if [ -z "$OP_METRICS_STR" ]; then
                OP_METRICS_STR="$OP_ENTRY"
            else
                OP_METRICS_STR="${OP_METRICS_STR};${OP_ENTRY}"
            fi
        done

        printf " %s" "$OP_METRICS_STR" >> "$OUT_UTIL"
        printf " %s\n" "$OP_METRICS_STR"
    done

    printf "\n" >> "$OUT"
    printf "\n" >> "$OUT_UTIL"
done