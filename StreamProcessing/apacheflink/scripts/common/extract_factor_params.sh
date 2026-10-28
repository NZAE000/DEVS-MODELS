#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------------
# Input arguments
# -------------------------
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 load-sweep/<app_dir>/sweeps/load-sweep-<app>.txt load-sweep/<app_dir>/sweeps/load-sweep-util-<app>.txt"
    exit 1
fi

INPUT="$1"
INPUT_UTIL="$2"

# -------------------------
# Get script directory
# -------------------------
DIR_BASE="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null &&
    pwd
)" || exit 1

cd "$DIR_BASE" || exit 1

# -------------------------
# Parse app names
# -------------------------
INPUT_FILENAME="$(basename -- "$INPUT")"
INPUT_UTIL_FILENAME="$(basename -- "$INPUT_UTIL")"

# Remove .txt extension.
APP="${INPUT_FILENAME%.txt}"
APP_UTIL="${INPUT_UTIL_FILENAME%.txt}"

# Extract text after the last '-'.
APP="${APP##*-}"
APP_UTIL="${APP_UTIL##*-}"

# -------------------------
# Parse app directories
# -------------------------
APP_DIR="$(basename -- "$(dirname -- "$(dirname -- "$INPUT")")")"
APP_DIR_UTIL="$(basename -- "$(dirname -- "$(dirname -- "$INPUT_UTIL")")")"

# -------------------------
# Validate app names
# -------------------------
if [[ "$APP" != "$APP_UTIL" ]]; then
    echo "ERROR: input files belong to different applications" >&2
    echo "  INPUT      -> $APP" >&2
    echo "  INPUT_UTIL -> $APP_UTIL" >&2
    exit 1
fi

# -------------------------
# Validate app directories
# -------------------------
if [[ "$APP_DIR" != "$APP_DIR_UTIL" ]]; then
    echo "ERROR: input files belong to different application directories" >&2
    echo "  INPUT      -> $APP_DIR" >&2
    echo "  INPUT_UTIL -> $APP_DIR_UTIL" >&2
    exit 1
fi

# -------------------------
# Build expected paths
# -------------------------
INPUT_PATH="$DIR_BASE/../../load-sweep/${APP_DIR}/sweeps/load-sweep-${APP}.txt"
INPUT_UTIL_PATH="$DIR_BASE/../../load-sweep/${APP_DIR}/sweeps/load-sweep-util-${APP}.txt"

# -------------------------
# Verify files existence
# -------------------------
if [[ ! -f "$INPUT_PATH" ]]; then
    echo "ERROR: load sweep file does not exist: $INPUT_PATH" >&2
    exit 1
fi

if [[ ! -f "$INPUT_UTIL_PATH" ]]; then
    echo "ERROR: load sweep utilization file does not exist: $INPUT_UTIL_PATH" >&2
    exit 1
fi

# -------------------------
# Output files
# -------------------------
OUTPUT="$DIR_BASE/../../load-sweep/${APP_DIR}/param-factors/degrad-params-${APP}.txt"
OUTPUT_UTIL="$DIR_BASE/../../load-sweep/${APP_DIR}/param-factors/w-params-${APP}.txt"

# Clean
> "$OUTPUT"
> "$OUTPUT_UTIL"

###############################################################################
# DEGRADATION PARAMETERS
#
# Output format:
#
#   P CPUmax Finter Fsatu Fineff Fdegrad
#
# Three degradation phases are identified:
#
#   1. Interference:
#        P <= Psat
#
#   2. Saturation:
#        Psat < P <= Pineff
#
#   3. Parallelism inefficiency:
#        P > Pineff
#
# A saturated workload region is independently detected for every P. It starts
# at the first workload reaching 98% of Tmax(P) and includes all subsequent
# higher-load workloads.
#
# Saturated throughput:
#
#   Tsat(P) = mean(TP(P,load)), load in saturated region
#
# Active CPU demand per processed event:
#
#   Dcpu(P,load) = Ucpu(P,load) / TP(P,load)
#
#   DcpuSat(P) = mean(Dcpu(P,load)), load in saturated region
#
# Effective wall-clock demand per processed event and replica:
#
#   Dwall(P) = P / Tsat(P)
#
# Psat is detected from a sustained collapse in marginal scaling gain:
#
#   G(Pi -> Pj)
#       = (Tsat(Pj) - Tsat(Pi))
#         / ((Pj - Pi) * Tsat(1))
#
# Psat is the beginning of the first sequence of two consecutive intervals
# whose normalized marginal gain is below 0.15. This means that each
# additional unit of parallelism contributes less than 15% of the baseline
# P=1 saturated capacity for at least two consecutive intervals.
#
# If no sustained knee is found, the first single low-gain interval is used.
# If no low-gain interval exists, saturation is considered not observed until
# the highest tested P.
#
# Pineff is the last P still reaching 99% of the global saturated capacity.
#
# Interference:
#
#   Finter(P) = Dwall(P) / Dwall(1)                if P <= Psat
#   Finter(P) = Finter(Psat)                       if P > Psat
#
# Saturation:
#
#   FcpuSat(P)  = DcpuSat(P) / DcpuSat(Psat)
#   FwallSat(P) = Dwall(P) / Dwall(Psat)
#
# Both signals describe different aspects of the same saturated regime.
# Their geometric mean is used so neither CPU demand nor total wall demand
# alone determines the service-time degradation:
#
#   Fsatu(P) = sqrt(FcpuSat(P) * FwallSat(P))      if Psat < P <= Pineff
#   Fsatu(P) = Fsatu(Pineff)                       if P > Pineff
#
# Parallelism inefficiency:
#
# CPU-side increase:
#
#   FcpuIneff(P) = DcpuSat(P) / DcpuSat(Pineff)
#
# Wall-clock loss beyond the saturated plateau:
#
#   FwallIneff(P) = Tsat(Pineff) / Tsat(P)
#
# The P/Pineff growth is intentionally excluded here because the saturation
# phase already represents the lack of useful scaling before Pineff.
#
#   Fineff(P) = sqrt(FcpuIneff(P) * FwallIneff(P)) if P > Pineff
#
# Final degradation:
#
#   Fdegrad(P) = Finter(P) * Fsatu(P) * Fineff(P)
#
# Each phase is incremental:
#
#   - Finter stops changing at Psat.
#   - Fsatu starts after Psat and stops changing at Pineff.
#   - Fineff starts only after Pineff.
#
# All parameters are derived exclusively from the real Flink load sweep.
###############################################################################
awk '
BEGIN {
    LOAD_SAT_FRACTION = 0.98
    KNEE_GAIN_THRESHOLD = 0.15
    KNEE_CONSECUTIVE = 2
    PINEFF_FRACTION = 0.99
}

NR == 1 { next }

{
    p = $1
    P_list[++nP] = p
    max_tp = -1.0
    max_cpu = -1.0
    max_idx = -1

    ###########################################################################
    # READ WORKLOAD MEASUREMENTS
    ###########################################################################
    for (i = 2; i <= NF; i++) {
        split($i, a, ":")
        tp[p, i] = a[2] + 0.0
        cpu[p, i] = a[3] + 0.0

        if (tp[p, i] > max_tp) {
            max_tp = tp[p, i]
            max_idx = i
        }

        if (cpu[p, i] > max_cpu)
            max_cpu = cpu[p, i]
    }

    Tmax[p] = max_tp
    CPUmax[p] = max_cpu

    ###########################################################################
    # DETECT SATURATED WORKLOAD REGION
    ###########################################################################
    sat_start[p] = -1

    for (i = 2; i <= NF; i++) {
        if (tp[p, i] >= LOAD_SAT_FRACTION * Tmax[p]) {
            sat_start[p] = i
            break
        }
    }

    if (sat_start[p] < 0)
        sat_start[p] = max_idx

    ###########################################################################
    # SATURATED THROUGHPUT AND ACTIVE CPU DEMAND
    #
    # Tsat(P)    = mean(TP)
    # DcpuSat(P) = mean(Ucpu / TP)
    ###########################################################################
    sum_tsat = 0.0
    sum_dcpu = 0.0
    sat_count = 0

    for (i = sat_start[p]; i <= NF; i++) {
        if (tp[p, i] <= 0)
            continue

        sum_tsat += tp[p, i]
        sum_dcpu += cpu[p, i] / tp[p, i]
        sat_count++
    }

    if (sat_count > 0) {
        Tsat[p] = sum_tsat / sat_count
        DcpuSat[p] = sum_dcpu / sat_count
    }
    else {
        Tsat[p] = Tmax[p]

        if (Tmax[p] > 0)
            DcpuSat[p] = cpu[p, max_idx] / Tmax[p]
        else
            DcpuSat[p] = 0.0
    }

    ###########################################################################
    # EFFECTIVE WALL-CLOCK DEMAND
    #
    # Dwall(P) = P / Tsat(P)
    ###########################################################################
    if (Tsat[p] > 0)
        Dwall[p] = p / Tsat[p]
    else
        Dwall[p] = 0.0
}

END {
    ###########################################################################
    # SORT PARALLELISM LEVELS
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

    if (Tsat[1] <= 0 || Dwall[1] <= 0) {
        print "ERROR: P=1 saturated reference was not found or is invalid" > "/dev/stderr"
        exit 1
    }

    ###########################################################################
    # GLOBAL SATURATED PEAK CAPACITY
    ###########################################################################
    global_tsat = -1.0

    for (i = 1; i <= nP; i++) {
        p = P_list[i]

        if (Tsat[p] > global_tsat)
            global_tsat = Tsat[p]
    }

    if (global_tsat <= 0) {
        print "ERROR: invalid global saturated throughput" > "/dev/stderr"
        exit 1
    }

    ###########################################################################
    # NORMALIZED MARGINAL SCALING GAIN
    #
    # G(Pi -> Pj)
    #     = (Tsat(Pj) - Tsat(Pi))
    #       / ((Pj - Pi) * Tsat(1))
    #
    # The normalization by Tsat(1) makes the criterion independent of the
    # absolute throughput scale of the application.
    ###########################################################################
    for (i = 1; i < nP; i++) {
        p_current = P_list[i]
        p_next = P_list[i + 1]
        delta_p = p_next - p_current

        if (delta_p > 0)
            marginal_gain[i] = (Tsat[p_next] - Tsat[p_current]) / (delta_p * Tsat[1])
        else
            marginal_gain[i] = 1.0
    }

    ###########################################################################
    # DETECT Psat
    #
    # Psat is the beginning of the first sequence of KNEE_CONSECUTIVE
    # intervals whose normalized marginal gain remains below the threshold.
    ###########################################################################
    Psat = -1
    sustained_low_gain = 0
    knee_mode = 0

    for (i = 1; i < nP; i++) {
        if (marginal_gain[i] < KNEE_GAIN_THRESHOLD)
            sustained_low_gain++
        else
            sustained_low_gain = 0

        if (sustained_low_gain >= KNEE_CONSECUTIVE) {
            knee_start_idx = i - KNEE_CONSECUTIVE + 1
            Psat = P_list[knee_start_idx]
            knee_mode = 1
            break
        }
    }

    ###########################################################################
    # FALLBACK 1:
    # If no sustained knee exists, use the first individual low-gain interval.
    ###########################################################################
    if (Psat < 0) {
        for (i = 1; i < nP; i++) {
            if (marginal_gain[i] < KNEE_GAIN_THRESHOLD) {
                Psat = P_list[i]
                knee_mode = 2
                break
            }
        }
    }

    ###########################################################################
    # FALLBACK 2:
    # If all intervals still provide significant scaling gain, saturation was
    # not observed before the highest tested parallelism.
    ###########################################################################
    if (Psat < 0) {
        Psat = P_list[nP]
        knee_mode = 3
    }

    ###########################################################################
    # DETECT Pineff
    #
    # Last P still reaching 99% of the global saturated capacity.
    ###########################################################################
    Pineff = Psat

    for (i = 1; i <= nP; i++) {
        p = P_list[i]

        if (p >= Psat && Tsat[p] >= PINEFF_FRACTION * global_tsat)
            Pineff = p
    }

    if (Pineff < Psat)
        Pineff = Psat

    if (DcpuSat[Psat] <= 0 || Dwall[Psat] <= 0) {
        print "ERROR: invalid degradation reference at Psat" > "/dev/stderr"
        exit 1
    }

    if (DcpuSat[Pineff] <= 0 || Dwall[Pineff] <= 0) {
        print "ERROR: invalid degradation reference at Pineff" > "/dev/stderr"
        exit 1
    }

    ###########################################################################
    # INTERFERENCE FACTOR
    #
    # Finter(P) = Dwall(P) / Dwall(1)
    #
    # Since:
    #
    #   Dwall(P) / Dwall(1)
    #       = (P / Tsat(P)) / (1 / Tsat(1))
    #       = P * Tsat(1) / Tsat(P)
    #
    # Finter is only allowed to evolve until Psat.
    ###########################################################################
    for (i = 1; i <= nP; i++) {
        p = P_list[i]

        if (p <= Psat) {
            if (Dwall[p] > 0)
                Finter[p] = Dwall[p] / Dwall[1]
            else
                Finter[p] = 1.0

            if (Finter[p] < 1.0)
                Finter[p] = 1.0
        }
    }

    Finter_sat = Finter[Psat]

    ###########################################################################
    # SATURATION FACTOR AT Pineff
    ###########################################################################
    Fcpu_sat_pineff = DcpuSat[Pineff] / DcpuSat[Psat]
    Fwall_sat_pineff = Dwall[Pineff] / Dwall[Psat]

    if (Fcpu_sat_pineff < 1.0)
        Fcpu_sat_pineff = 1.0

    if (Fwall_sat_pineff < 1.0)
        Fwall_sat_pineff = 1.0

    Fsatu_pineff = sqrt(Fcpu_sat_pineff * Fwall_sat_pineff)

    ###########################################################################
    # EXTRACT THREE PHASE FACTORS
    ###########################################################################
    for (i = 1; i <= nP; i++) {
        p = P_list[i]

        #######################################################################
        # PHASE 1: INTERFERENCE
        #######################################################################
        if (p <= Psat) {
            Fsatu[p] = 1.0
            Fineff[p] = 1.0
        }

        #######################################################################
        # PHASE 2: SATURATION
        #######################################################################
        else if (p <= Pineff) {
            Finter[p] = Finter_sat
            Fcpu_sat = DcpuSat[p] / DcpuSat[Psat]
            Fwall_sat = Dwall[p] / Dwall[Psat]

            if (Fcpu_sat < 1.0)
                Fcpu_sat = 1.0

            if (Fwall_sat < 1.0)
                Fwall_sat = 1.0

            Fsatu[p] = sqrt(Fcpu_sat * Fwall_sat)
            Fineff[p] = 1.0
        }

        ########################################################################
        # PHASE 3: PARALLELISM INEFFICIENCY
        ########################################################################
        else {
            Finter[p] = Finter_sat
            Fsatu[p] = Fsatu_pineff

            ####################################################################
            # COLLAPSED SATURATION PHASE
            #
            # When Psat == Pineff there is no explicit saturation interval.
            # Therefore, the P/Pineff loss of useful parallel scaling has not
            # been represented by Fsatu and must be included here through the
            # complete wall-clock demand ratio.
            ####################################################################
            if (Pineff == Psat) {
                Fineff[p] = Dwall[p] / Dwall[Pineff]

                if (Fineff[p] < 1.0)
                    Fineff[p] = 1.0
            }

            ####################################################################
            # NORMAL CASE
            ####################################################################
            else {
                Fcpu_ineff = DcpuSat[p] / DcpuSat[Pineff]
                Fwall_ineff = Tsat[Pineff] / Tsat[p]

                if (Fcpu_ineff < 1.0)
                    Fcpu_ineff = 1.0

                if (Fwall_ineff < 1.0)
                    Fwall_ineff = 1.0

                Fineff[p] = sqrt(Fcpu_ineff * Fwall_ineff)
            }
        }

        #######################################################################
        # FINAL DEGRADATION
        #######################################################################
        Fdegrad[p] = Finter[p] * Fsatu[p] * Fineff[p]

        printf "%d %.6f %.6f %.6f %.6f %.6f\n", p, CPUmax[p], Finter[p], Fsatu[p], Fineff[p], Fdegrad[p] >> "'"$OUTPUT"'"
    }

    ###########################################################################
    # DIAGNOSTIC INFORMATION
    ###########################################################################
    print "# Knee gain threshold =", KNEE_GAIN_THRESHOLD > "/dev/stderr"
    print "# Knee consecutive intervals =", KNEE_CONSECUTIVE > "/dev/stderr"

    for (i = 1; i < nP; i++)
        printf "# Marginal gain P=%d->%d = %.6f\n", P_list[i], P_list[i + 1], marginal_gain[i] > "/dev/stderr"

    print "# Detected Psat =", Psat > "/dev/stderr"

    if (knee_mode == 1)
        print "# Psat detection = sustained marginal-gain knee" > "/dev/stderr"
    else if (knee_mode == 2)
        print "# Psat detection = first low-gain interval fallback" > "/dev/stderr"
    else
        print "# Psat detection = no knee observed; highest P used" > "/dev/stderr"

    print "# Detected Pineff =", Pineff > "/dev/stderr"
    print "# Global Tsat =", global_tsat > "/dev/stderr"
    print "# Tmax(Psat) =", Tmax[Psat] > "/dev/stderr"
    print "# Tmax(Pineff) =", Tmax[Pineff] > "/dev/stderr"
    print "# Tsat(1) =", Tsat[1] > "/dev/stderr"
    print "# Tsat(Psat) =", Tsat[Psat] > "/dev/stderr"
    print "# Tsat(Pineff) =", Tsat[Pineff] > "/dev/stderr"
    print "# DcpuSat(Psat) =", DcpuSat[Psat] > "/dev/stderr"
    print "# DcpuSat(Pineff) =", DcpuSat[Pineff] > "/dev/stderr"
    print "# Dwall(Psat) =", Dwall[Psat] > "/dev/stderr"
    print "# Dwall(Pineff) =", Dwall[Pineff] > "/dev/stderr"
    print "# FcpuSat(Pineff) =", Fcpu_sat_pineff > "/dev/stderr"
    print "# FwallSat(Pineff) =", Fwall_sat_pineff > "/dev/stderr"
    print "# Fsatu(Pineff) =", Fsatu_pineff > "/dev/stderr"
}
' "$INPUT_PATH"

###############################################################################
# INTERNAL OCCUPATION PARAMETERS
#
# Utilization sweep format:
#
#   operator:InRecords-OutRecords-BusyTime-Utilization
#
# BusyTime is the average accumulated busy time per replica:
#
#   BusyTime(op,P,load)
#       = AccumBusyTime(op,P,load) / P
#
# The number of processed records is selected according to the operator:
#
#   ServiceCount(op,P,load)
#       = InRecords                            if InRecords > 0
#       = OutRecords                           otherwise
#
# This makes InRecords the primary service count for regular operators,
# filters, joins and sinks. Sources normally have InRecords=0, so OutRecords
# is used instead.
#
# Occupation per processed event:
#
#   OccupationPerEvent(op,P,load)
#       = BusyTime(op,P,load) * P
#         / ServiceCount(op,P,load)
#
# Since:
#
#   BusyTime = AccumBusyTime / P
#
# this is equivalent to:
#
#   OccupationPerEvent
#       = AccumBusyTime / ServiceCount
#
# Therefore, the occupation estimate no longer depends on application-level
# throughput or finishing time.
#
# Saturated workloads are still selected from the first workload reaching
# 98% of Tmax(P) through the highest tested load.
#
# OccupationPerEvent(op,P) is the average of the per-workload occupation
# values inside that saturated region.
#
# InternalOccupation(op,P)
#       = OccupationPerEvent(op,P)
#         / OccupationPerEvent(op,1)
#
# End use:
#
#   accumBusy += t_base_op * InternalOccupation(op,P)
###############################################################################
awk '
BEGIN {
    SAT_FRACTION = 0.98
}

###############################################################################
# FIRST FILE:
# Read application throughput for every P/workload pair and detect the
# saturated workload region.
#
# Global throughput is used only to identify the saturated region. It is no
# longer used to calculate operator occupation per event.
###############################################################################
FNR == NR {
    if (FNR == 1)
        next

    p = $1
    max_tp = -1.0
    max_idx = -1

    for (i = 2; i <= NF; i++) {
        split($i, a, ":")
        TP[p, i] = a[2] + 0.0

        if (TP[p, i] > max_tp) {
            max_tp = TP[p, i]
            max_idx = i
        }
    }

    Tmax[p] = max_tp
    sat_start[p] = -1

    # The saturated region begins at the first workload reaching 98% of Tmax.
    for (i = 2; i <= NF; i++) {
        if (TP[p, i] >= SAT_FRACTION * max_tp) {
            sat_start[p] = i
            break
        }
    }

    if (sat_start[p] < 0)
        sat_start[p] = max_idx

    next
}

###############################################################################
# SECOND FILE:
#
# Expected operator format:
#
#   operator:InRecords-OutRecords-BusyTime-Utilization
#
# Calculate operator-specific occupation per processed event using the actual
# operator record count instead of global application throughput.
###############################################################################
FNR == 1 { next }

{
    p = $1

    if (!(p in seen_p)) {
        seen_p[p] = 1
        P_list[++nP] = p
    }

    start = sat_start[p]

    if (start < 2)
        start = 2

    # Use all workloads from the beginning of saturation onward. This includes
    # the overload region, where throughput can flatten or decrease.
    for (i = start; i <= NF; i++) {
        n_pairs = split($i, ops, ";")

        for (j = 1; j <= n_pairs; j++) {
            if (ops[j] == "")
                continue

            n_kv = split(ops[j], kv, ":")

            if (n_kv < 2)
                continue

            op = kv[1]
            n_metrics = split(kv[2], metrics, "-")

            if (op == "" || n_metrics < 4)
                continue

            in_records = metrics[1] + 0.0
            out_records = metrics[2] + 0.0
            busy_time = metrics[3] + 0.0
            util = metrics[4] + 0.0

            ###################################################################
            # SELECT OPERATOR SERVICE COUNT
            #
            # Regular operators:
            #   process one invocation for every input record.
            #
            # Sources:
            #   normally have no input records, so emitted records are used.
            ###################################################################
            if (in_records > 0)
                service_count = in_records
            else if (out_records > 0)
                service_count = out_records
            else
                continue

            key = p SUBSEP op

            ###################################################################
            # OCCUPATION PER PROCESSED EVENT
            #
            # BusyTime is already averaged across P replicas:
            #
            #   W = BusyTime * P / ServiceCount
            #
            # which is equivalent to:
            #
            #   W = AccumBusyTime / ServiceCount
            ###################################################################
            W_sample = (busy_time * p) / service_count
            W_sum[key] += W_sample
            W_count[key] += 1

            # Keep auxiliary metrics for diagnostics.
            N_sum[key] += service_count
            In_sum[key] += in_records
            Out_sum[key] += out_records
            Busy_sum[key] += busy_time
            Util_sum[key] += util

            if (!(op in seen_op)) {
                seen_op[op] = 1
                op_order[++n_ops] = op
            }
        }
    }
}

END {
    ###########################################################################
    # SORT PARALLELISM LEVELS
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
    # AVERAGE OCCUPATION PER EVENT ACROSS SATURATED WORKLOADS
    ###########################################################################
    for (k = 1; k <= n_ops; k++) {
        op = op_order[k]

        for (i = 1; i <= nP; i++) {
            p = P_list[i]
            key = p SUBSEP op

            if (W_count[key] > 0)
                W[p, op] = W_sum[key] / W_count[key]
            else
                W[p, op] = 0.0
        }
    }

    ###########################################################################
    # BASELINE P=1
    #
    # P=1 defines the intrinsic reference occupation per processed event for
    # every operator.
    ###########################################################################
    for (k = 1; k <= n_ops; k++) {
        op = op_order[k]
        W_ref[op] = W[1, op]
    }

    ###########################################################################
    # INTERNAL OCCUPATION FACTOR
    #
    # InternalOccupation(op,P)
    #     = W(op,P) / W(op,1)
    ###########################################################################
    for (i = 1; i <= nP; i++) {
        p = P_list[i]

        for (k = 1; k <= n_ops; k++) {
            op = op_order[k]

            if (W_ref[op] > 0)
                stall[p, op] = W[p, op] / W_ref[op]
            else
                stall[p, op] = 1.0

            # InternalOccupation represents additional occupation only.
            if (stall[p, op] < 1.0)
                stall[p, op] = 1.0

            printf "op=%-20s, p=%d, Wp=%e, W1=%e, Stall=%f\n", op, p, W[p, op], W_ref[op], stall[p, op]
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
    # OUTPUT HEADER
    ###########################################################################
    printf "%-*s", max_len, "opname" > "'"$OUTPUT_UTIL"'"

    for (i = 1; i <= nP; i++)
        printf "%13d", P_list[i] >> "'"$OUTPUT_UTIL"'"

    printf "\n" >> "'"$OUTPUT_UTIL"'"

    ###########################################################################
    # OUTPUT ROWS
    ###########################################################################
    for (k = 1; k <= n_ops; k++) {
        op = op_order[k]
        printf "%-*s", max_len, op >> "'"$OUTPUT_UTIL"'"

        for (i = 1; i <= nP; i++) {
            p = P_list[i]
            printf "%13.6f", stall[p, op] >> "'"$OUTPUT_UTIL"'"
        }

        printf "\n" >> "'"$OUTPUT_UTIL"'"
    }
}
' "$INPUT_PATH" "$INPUT_UTIL_PATH"