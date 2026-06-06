#!/bin/bash
# -----------------------------------------------------
# generate_operator_parameters.sh  (picoseconds version)
# Lee operators/operators_list.txt que contiene:
#   id ; name ; parallelism ; next1-next2 ; ship_strategy
# Genera:
#   operator.txt   → propiedades con ship strategy
#   topology.txt   → conexiones ordered source→sink
# -----------------------------------------------------

METRICS_DIR="metrics"
OPERLIST_DIR="operators/operators_list.txt"

OUTPUT_PROP_FILE="../input_data/operator.txt"
OUTPUT_TOPO_FILE="../input_data/topology.txt"
OUTPUT_DEG_FILE="../input_data/degradation.txt"
OUTPUT_OCCUP_FILE="../input_data/extraoccupation.txt"

SCALE=1000000000   # ms → ps

# Clean outputs
> "$OUTPUT_PROP_FILE"
> "$OUTPUT_TOPO_FILE"
> "$OUTPUT_DEG_FILE"
> "$OUTPUT_OCCUP_FILE"

# Write degradation factors by default.
printf "%d %d %d %d %f\n" "0" "0" "0" "0" "1.0" >> "$OUTPUT_DEG_FILE"


echo "[INFO] Generating operator's parameters..."

#######################################################################
# 1. GENERAR operator.txt
#######################################################################
while IFS=';' read -r OPER_ID OPER_NAME PARALLELISM NEXTS SHIP_STRATEGY; do

    FILE="$METRICS_DIR"/"$OPER_NAME".txt
    echo "[INFO] Processing $OPER_NAME ..."

    read_records=$(grep "read-records;" "$FILE" | cut -d';' -f2)
    write_records=$(grep "write-records;" "$FILE" | cut -d';' -f2)
    SELECTIVITY=1.0

    if [[ "$write_records" != "0" && "$read_records > 0" ]]; then
        SELECTIVITY=$(echo "$write_records / $read_records" | bc -l)
    fi

    # Write occupation factor inemdiatly by default.
    printf "%-20s %f\n" "$OPER_NAME" "1.0" >> "$OUTPUT_OCCUP_FILE"

    busy_time_ps=$(echo "$(grep "accumulateBusyTimeMs;" "$FILE" | cut -d';' -f2) * $SCALE" | bc -l)
    stddev_ps=$(echo "$(grep "mailboxLatencyMs_stddev;" "$FILE" | cut -d';' -f2) * $SCALE" | bc -l)
    p95_ps=$(echo "$(grep "mailboxLatencyMs_p95;" "$FILE" | cut -d';' -f2) * $SCALE" | bc -l)
    p99_ps=$(echo "$(grep "mailboxLatencyMs_p99;" "$FILE" | cut -d';' -f2) * $SCALE" | bc -l)

    if [[ -z "$read_records" || "$read_records" == "0" ]]; then
        printf "%-20s %d %-8s %s %s %s\n" "$OPER_NAME" "$PARALLELISM" "fix" "1" "$SHIP_STRATEGY" "$SELECTIVITY" >> "$OUTPUT_PROP_FILE"
        echo "  -> numRecords_in=0, usando fix 1"
        continue
    fi

    mu_ps=$(echo "$busy_time_ps / $read_records" | bc -l)
    #sigma_ps=$(echo "$stddev_ps" | bc -l)
    sigma_ps_raw=$(echo "$stddev_ps" | bc -l)
    sigma_min=$(echo "0.05 * $mu_ps" | bc -l)
    sigma_ps=$(echo "$sigma_ps_raw > $sigma_min" | bc -l)
    if [[ "$sigma_ps" -eq 1 ]]; then
        sigma_ps=$sigma_ps_raw
    else
        sigma_ps=$sigma_min
    fi

    lambda_ps=$(echo "1 / $mu_ps" | bc -l)
    cv=$(echo "$sigma_ps / $mu_ps" | bc -l)

    if [[ -n "$p95_ps" && -n "$p99_ps" && $(echo "$sigma_ps > 0" | bc -l) -eq 1 ]]; then
        cola_ratio=$(echo "( $p99_ps - $p95_ps ) / $sigma_ps" | bc -l)
    else
        cola_ratio=0
    fi

    # --- SELECT DISTRIBUTION ---
    DIST="fix"; ARGS="$mu_ps"

    #DIST=""; ARGS=""
    #if (( $(echo "$cv < 0.1" | bc -l) )); then
    #    DIST="fix"
    #    ARGS="$mu_ps"
#
    #elif (( $(echo "$cv <= 0.5" | bc -l) )) && (( $(echo "$cola_ratio <= 2.0" | bc -l) )); then
    #    DIST="norm"
    #    ARGS="$mu_ps $sigma_ps"
#
    #elif (( $(echo "$cv <= 1.0" | bc -l) )) && (( $(echo "$cola_ratio <= 3.5" | bc -l) )); then
    #    DIST="gamm"
    #    v=$(echo "$sigma_ps * $sigma_ps" | bc -l)
    #    k=$(echo "($mu_ps * $mu_ps) / $v" | bc -l)
    #    theta=$(echo "$v / $mu_ps" | bc -l)
    #    ARGS="$k $theta"
#
    #elif (( $(echo "$cv > 1.0" | bc -l) )) || (( $(echo "$cola_ratio > 3.5" | bc -l) )); then
    #    DIST="lnorm"
    #    v=$(echo "$sigma_ps * $sigma_ps" | bc -l)
    #    sigma_ln=$(echo "sqrt( l(1 + $v / ($mu_ps * $mu_ps)) )" | bc -l)
    #    mu_ln=$(echo "l($mu_ps) - ($sigma_ln * $sigma_ln)/2" | bc -l)
    #    ARGS="$mu_ln $sigma_ln"
#
    #else
    #    DIST="expo"
    #    ARGS="$lambda_ps"
    #fi

    # -- NUEVO FORMATO: name parallelism distribution params ship_strategy --
    printf "%-20s %d %-8s %s %s %s\n" \
        "$OPER_NAME" "$PARALLELISM" "$DIST" "$ARGS" "$SHIP_STRATEGY" "$SELECTIVITY" \
        >> "$OUTPUT_PROP_FILE"


done < "$OPERLIST_DIR"

echo "[SUCCESS] operator.txt generated."

#######################################################################
# 2. GENERAR topology.txt usando SOLO operators_list.txt
#######################################################################
echo "[INFO] Generating topology from operators_list.txt..."

# operators_list.txt ya está en orden source→sink
# Formato: ID ; NAME ; PAR ; NEXT1-NEXT2 ; SHIP
while IFS=';' read -r ID NAME PAR NEXTS SHIP; do

    # NEXTS puede ser: "0" o "A-B-C"
    if [[ "$NEXTS" == "0" ]]; then
        continue
    fi

    # separar sucesores
    IFS='-' read -ra TARGETS <<< "$NEXTS"

    for T in "${TARGETS[@]}"; do
        # convertir ID destino → name destino
        TO_NAME=$(grep "^$T;" "$OPERLIST_DIR" | cut -d';' -f2)

        if [[ -n "$TO_NAME" ]]; then
            echo "$NAME $TO_NAME" >> "$OUTPUT_TOPO_FILE"
        fi
    done

done < "$OPERLIST_DIR"

echo "[SUCCESS] topology.txt generated."
echo "---------------------------------------------"
echo ""
