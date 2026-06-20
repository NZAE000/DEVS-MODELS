#!/bin/bash

# -------------------------
# Input arguments
# -------------------------
if [ $# -lt 2 ]; then
    echo "Usage: $0 l load-sweep/load-sweep-app.txt  load-sweep/load-sweep-util-app.txt"
    exit 1
fi

INPUT="$1"
INPUT_UTIL="$2"

# -------------------------
# Parse app name (desde INPUT)
# -------------------------
APP=$(echo "$INPUT" | cut -d'.' -f1 | cut -d'-' -f4)
APP_UTIL=$(echo "$INPUT_UTIL" | cut -d'.' -f1 | cut -d'-' -f5)

if [ "$APP" != "$APP_UTIL" ]; then
    echo "WARNING: input files seem to belong to different apps"
    echo "  INPUT      -> $APP"
    echo "  INPUT_UTIL -> $APP_UTIL"
    exit 1
fi

# Clean
OUTPUT="load-sweep/degrad-params-${APP}.txt"
> "$OUTPUT"
OUTPUT_UTIL="load-sweep/w-params-${APP}.txt"
> "$OUTPUT_UTIL"


awk '
###############################################################################
# FIRST PASS: Read data and extract basic metrics
###############################################################################
NR == 1 { next }   # saltar header

{
    p = $1
    max_tp = -1
    max_cpu = -1
    sat_idx = -1

# Read metrics by load configuration
    for (i = 2; i <= NF; i++) {
        split($i, a, ":")
        tp[i]  = a[2]
        cpu[i] = a[3]

        if (cpu[i] > max_cpu){
            max_cpu = cpu[i]
        }

        if (tp[i] > max_tp) {
            max_tp = tp[i]
            sat_idx = i
        }
    }

# Save list of P, Tmax, CPUMax and U_sat
    P_list[++nP] = p
    Tmax[p] = max_tp
    CPUmax[p] = max_cpu
    printf("P=%d, Tmax=%.4f, CPUmax=%.4f\n", p, Tmax[p], CPUmax[p]);

    # Save reference throughput (better early scaling)
    if (p == 1)
        T_ref = max_tp

    # U_sat
    U_sat[p] = cpu[sat_idx]

# Search U_thr (95% of maximum throughput)
    thr_idx = -1
    for (i = 2; i <= NF; i++) {
        if (tp[i] >= 0.95 * max_tp) {
            thr_idx = i
            break
        }
    }

    if (thr_idx == -1)
        next

    U_thr[p] = cpu[thr_idx]
    S_thr = tp[thr_idx]

# Calculate alpha (interference)
    num = 0.0
    den = 0.0

    for (i = thr_idx + 1; i <= sat_idx; i++) {
        dU = cpu[i] - U_thr[p]
        dS = (S_thr - tp[i]) / S_thr

        if (dU > 0 && dS > 0) {
            num += dS
            den += dU
        }
    }

    if (den > 0)
        alpha[p] = num / den
    else
        alpha[p] = 0.0
}

###############################################################################
# SECOND PASS: detect P0 (global stable maximum)
###############################################################################
END {

    eps = 0.01          # 1% tolerance
    P0 = P_list[nP]     # fallback: last P

    for (i = 1; i <= nP; i++) {
        p_i = P_list[i]
        Ti = Tmax[p_i]
        stable = 1

        for (j = i + 1; j <= nP; j++) {
            p_j = P_list[j]
            if (Tmax[p_j] > (1.0 + eps) * Ti) {
                stable = 0
                break
            }
        }
        if (stable) {
            P0 = p_i
            break
        }
    }
    P0 = 12
    # Calculate average gamma post-P0
    sum_gamma = 0.0
    count = 0

    for (i = 1; i <= nP; i++) {
        p = P_list[i]
        if (p > P0) {
            slope = (Tmax[p] - Tmax[P0]) / (Tmax[P0] * (p - P0))
            sum_gamma += slope
            count++
        }
    }

    if (count > 0)
        gamma = sum_gamma / count
    else
        gamma = 0.0

    # Acotar gamma a rango estable
    if (gamma < 0.05) gamma = 0.05
    if (gamma > 0.5)  gamma = 0.5

    ############################################################################
    # FINAL OUTPUT WITH MONOTONIZATION OF E POST-P0
    # Format:
    # P  CPUmax  U_thr  alpha  U_sat  E
    ############################################################################

    prev_E = -1.0

    for (i = 1; i <= nP; i++) {
        p = P_list[i]

        # Paralelismo efectivo
        if (p <= P0)
            P_eff = p
        else
            P_eff = P0 + gamma * (p - P0)

        # Eficiencia paralela cruda
        if (T_ref > 0)
            E = Tmax[p] / (P_eff * T_ref)
        else
            E = 1.0

        # --------------------------------------------------
        # Monotoning of E post-P0
        # --------------------------------------------------
        if (p >= P0) {
            if (prev_E < 0)
                prev_E = E
            else if (E > prev_E){
                diff = (CPUmax[P_list[i]] - CPUmax[P_list[i-1]])
                factor = 0.96 - diff
                if (factor < 0.7) factor = 0.7 # To delimit
                prev_E = prev_E * factor
                E = prev_E
                printf "E = %.4f, CPUmax[p] = %.4f, CPUmax[p-1] = %.4f\n", E, CPUmax[P_list[i]], CPUmax[P_list[i-1]] 
            }
            else
                prev_E = E
        }

        printf "%d %.6f %.6f %.6f %.6f %.6f\n",
            p, CPUmax[p], U_thr[p], alpha[p], U_sat[p], E >> "'"$OUTPUT"'"
    }

    # Info
    print "# Detected P0 =", P0     > "/dev/stderr"
    print "# Computed gamma =", gamma > "/dev/stderr"
}
' "$INPUT"

###############################################################################
# THIRD PASS:
#
# Extract OCCUPANCY FACTOR per operator:
#
#   stallFactor(op,P)
#
# Model:
#
#   OccupationPerEvent(op,P)=U(op,P)/TP(P)
#
#   stallFactor(op,P)=
#       OccupationPerEvent(op,P)
#       --------------------------------
#       OccupationPerEvent(op,1)
#
# End use:
#
#   accumBusy += t_base_op * stallFactor(op,P)
#
###############################################################################
awk '

###############################################################################
# FIRST FILE:
# Read maximum throughput per P from INPUT
###############################################################################
FNR == NR && NR > 1 {

    p = $1

    max_tp = 0

    for (i = 2; i <= NF; i++) {

        split($i, a, ":")

        tp = a[2] + 0

        if (tp > max_tp)
            max_tp = tp
    }

    TP[p] = max_tp

    next
}

###############################################################################
# SECOND FILE:
# Read average utilization
###############################################################################
FNR == 1 { next }

{
    p = $1

    ###########################################################################
    # Save list P
    ###########################################################################
    if (!(p in seen_p)) {

        seen_p[p] = 1
        P_list[++nP] = p
    }

    ###########################################################################
    # Latest workloads
    ###########################################################################
    last = 2
    start = NF - last

    if (start < last)
        start = last

    for (i = start; i <= NF; i++) {

        split($i, ops, ";")

        for (j = 1; j <= length(ops); j++) {

            split(ops[j], kv, ":")

            op  = kv[1]
            val = kv[2] + 0
            #printf("aca: %-20s, util: %f\n", op, val);

            key = p "|" op

            sum[key] += val
            count[key] += 1

            ###################################################################
            # Order operators
            ###################################################################
            if (!(op in seen_op)) {

                seen_op[op] = 1
                op_order[++n_ops] = op
            }
        }
    }
}

END {

    ###########################################################################
    # ORDER P
    ###########################################################################
    for (i = 1; i <= nP; i++) {

        for (j = i + 1; j <= nP; j++) {

            if (P_list[i] > P_list[j]) {

                tmp = P_list[i]
                P_list[i] = P_list[j]
                P_list[j] = tmp
            }
        }
    }

    ###########################################################################
    # CALCULATE U(op,P)
    ###########################################################################
    for (k = 1; k <= n_ops; k++) {

        op = op_order[k]

        for (i = 1; i <= nP; i++) {

            p_i = P_list[i]
            key = p_i "|" op

            if (count[key] > 0)
                U[p_i, op] = sum[key] / count[key]
            else
                U[p_i, op] = 0
        }
    }

    ###########################################################################
    # OCCUPATION PER EVENT
    #
    # W(op,P) = (U(op,P) * P) /TP(P)
    ###########################################################################
    for (k = 1; k <= n_ops; k++) {

        op = op_order[k]
        
        for (i = 1; i <= nP; i++) {
            p_i = P_list[i]

            if (TP[p_i] > 0){
                W[p_i, op] = (U[p_i, op] * P_list[i])/ TP[p_i]
                #printf("Op=%-20s, P=%d, U=%f, Tmax=%f, W=%e\n", op, p_i,  U[p_i, op], TP[p_i], W[p_i, op]);
            }
            else{
                W[p_i, op] = 0
            }
                
        }
    }

    ###########################################################################
    # BASELINE P=1
    ###########################################################################
    for (k = 1; k <= n_ops; k++) {

        op = op_order[k]

        W_ref[op] = W[1, op]
    }

    ###########################################################################
    # STALL FACTOR
    #
    # stallFactor(op,P)=W(P)/W(1)
    ###########################################################################
    for (i = 1; i <= nP; i++) {

        p_i = P_list[i]

        for (k = 1; k <= n_ops; k++) {

            op = op_order[k]

            if (W_ref[op] > 0){
                stall[p_i, op] = W[p_i, op] / W_ref[op]
                #if (p_i==32)
                    printf("op=%-20s, p=%d, Wp=%e, W1=%e, Stall=%f\n",  op, p_i, W[p_i, op], W_ref[op], stall[p_i, op]);
            }
            else {
                stall[p_i, op] = 1
            }

            ###################################################################
            # Min clamp
            ###################################################################
            if (stall[p_i, op] < 1)
                stall[p_i, op] = 1
        }
    }

    ###########################################################################
    # MAX WIDTH OPERATOR
    ###########################################################################
    max_len = length("opname")

    for (k = 1; k <= n_ops; k++) {

        op = op_order[k]

        if (length(op) > max_len)
            max_len = length(op)
    }

    max_len += 2

    ###########################################################################
    # OUTPUT stallFactor(op,P)
    ###########################################################################
    printf "%-*s", max_len, "opname" > "'"$OUTPUT_UTIL"'"

    for (i = 1; i <= nP; i++) {

        printf "%13d",
               P_list[i] >> "'"$OUTPUT_UTIL"'"
    }

    printf "\n" >> "'"$OUTPUT_UTIL"'"

    ###########################################################################
    # ROWS
    ###########################################################################
    for (k = 1; k <= n_ops; k++) {

        op = op_order[k]

        printf "%-*s",
               max_len,
               op >> "'"$OUTPUT_UTIL"'"

        for (i = 1; i <= nP; i++) {

            p_i = P_list[i]

            printf "%13.6f",
                   stall[p_i, op] >> "'"$OUTPUT_UTIL"'"
        }

        printf "\n" >> "'"$OUTPUT_UTIL"'"
    }
}
' "$INPUT" "$INPUT_UTIL"