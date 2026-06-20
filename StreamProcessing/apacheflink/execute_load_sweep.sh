#!/bin/bash

# -------------------------
# Config file as argument
# -------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 load-sweep/cfg/load-sweep-app.cfg"
    exit 1
fi
CFG=$1
#CFG="load-sweep/load-sweep.cfg"

# -------------------------
# Parse app name
# -------------------------
APP=$(grep '^app:' "$CFG" | cut -d':' -f2 | xargs)


# -------------------------
# Output file name
# -------------------------
OUT="load-sweep/load-sweep-${APP}.txt"
OUT_UTIL="load-sweep/load-sweep-util-${APP}.txt"


# -------------------------
# Parse config
# -------------------------
N_SLOTS=$(grep '^slots:' "$CFG" | cut -d':' -f2 | xargs)
LOADS_RAW=$(awk -F': ' '/^loads:/ {print $2}' "$CFG")
P_RAW=$(awk -F': ' '/^p_levels:/ {print $2}' "$CFG")
N_RUNS=$(awk -F': ' '/^per_exec:/ {print $2}' "$CFG")

# Convert to arrays
IFS=',' read -ra LOADS <<< "$LOADS_RAW"
IFS=',' read -ra P_LEVELS <<< "$P_RAW"

# Trim spaces
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
} > "$OUT"
{
    printf "parallelism"
    for L in "${LOADS[@]}"; do
        printf " %s" "$L"
    done
    printf "\n"
} > "$OUT_UTIL"

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
        declare -a sum_util
        declare -a count_util
        op_names=()
        sum_util=()
        count_util=()

        for ((r=1; r<=N_RUNS; r++)); do
            TMP_OUT="/tmp/run_${APP}_${P}_${EVENTS}_${TPS}_$r.log"

            bash execute.sh "$APP" "$N_SLOTS" "$P" "$EVENTS" "$TPS" > "$TMP_OUT" 2>&1

            # -------------------------
            # EXTRACT TIME, THOUGHPUT AND CPU
            # -------------------------
            RESULT=$(grep "^FTime:" "$TMP_OUT" | tail -n 1)

            if [ -z "$RESULT" ]; then
                echo "WARNING: missing FTime (P=$P, L=$L, run=$r)" >&2
                continue
	        fi

            FT=$(echo "$RESULT" | cut -d',' -f1 | cut -d' ' -f2)
            TP=$(echo "$RESULT" | cut -d',' -f2 | cut -d' ' -f3)
            CPU=$(echo "$RESULT" | cut -d',' -f3 | cut -d' ' -f3)

            sum_ft=$(echo "$sum_ft + $FT" | bc -l)
            sum_tp=$(echo "$sum_tp + $TP" | bc -l)
            sum_cpu=$(echo "$sum_cpu + $CPU" | bc -l)
            ok_runs=$((ok_runs + 1))

            # -------------------------
            # EXTRACT UTILIZATIONS
            # -------------------------
            UTIL_BLOCK=$(awk '
                /^Operator/ {flag=1; next}
                flag && NF==0 {flag=0}
                flag
            ' "$TMP_OUT")

            idx=0

            while read -r line; do
                op=$(echo "$line" | awk '{print $1}')
                util=$(echo "$line" | awk '{print $5}')

                # Primera vez: guardar nombres
                if [ $r -eq 1 ]; then
                    op_names[$idx]="$op"
                    sum_util[$idx]=0
                    count_util[$idx]=0
                fi

                # Acumular
                sum_util[$idx]=$(echo "${sum_util[$idx]} + $util" | bc -l)
                count_util[$idx]=$(( ${count_util[$idx]} + 1 ))

                idx=$((idx + 1))
            done <<< "$UTIL_BLOCK"

            rm -f "$TMP_OUT"
            sleep 5
    	done

        # -------------------------
        # AVGS
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

        UTIL_STR=""
        for i in "${!op_names[@]}"; do
            avg_util=$(echo "${sum_util[$i]} / ${count_util[$i]}" | bc -l)

            if [ $i -eq 0 ]; then
                UTIL_STR="${op_names[$i]}:${avg_util}"
            else
                UTIL_STR="${UTIL_STR};${op_names[$i]}:${avg_util}"
            fi
        done

        printf " %s" "$UTIL_STR" >> "$OUT_UTIL"
        printf " %s\n" "$UTIL_STR"
    done

    printf "\n" >> "$OUT"
    printf "\n" >> "$OUT_UTIL"
done
