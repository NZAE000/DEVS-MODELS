#!/bin/bash

###############################################################################
#  move_degrad_and_occup_factors_to_sim_param.sh
#
# Use:
#
#   ./ move_degrad_and_occup_factors_to_sim_param.sh <app> <parallelism>
#
# e.g:
#
#   ./ move_degrad_and_occup_factors_to_sim_param.sh q3 16
#
###############################################################################

set -e

###############################################################################
# VALIDATION
###############################################################################
if [ $# -ne 2 ]; then
    echo "Uso: $0 <app> <parallelism>"
    exit 1
fi

APP="$1"
P="$2"

###############################################################################
# INPUT FILES
###############################################################################
DEGRAD_PARAMS_FILE="load-sweep/degrad-params-${APP}.txt"
W_PARAMS_FILE="load-sweep/w-params-${APP}.txt"

###############################################################################
# OUTPUT FILES
###############################################################################
DEGRAD_OUTPUT="../input_data/degradation.txt"
EXTRA_OUTPUT="../input_data/extraoccupation.txt"

###############################################################################
# VALIDATE IF EXISTS
###############################################################################
if [ ! -f "$DEGRAD_PARAMS_FILE" ]; then
    echo "ERROR: $DEGRAD_PARAMS_FILE no exists" 
    exit 1
fi

if [ ! -f "$W_PARAMS_FILE" ]; then
    echo "ERROR: $W_PARAMS_FILE no exists" 
    exit 1
fi

###############################################################################
# EXTRAXT DEGRADATION PARAMS
###############################################################################
DEGRAD_LINE=$(awk -v p="$P" '
$1 == p {

    printf "%s %s %s %s %s\n",
           $2, $3, $4, $5, $6
}
' "$DEGRAD_PARAMS_FILE")

if [ -z "$DEGRAD_LINE" ]; then
    echo "ERROR: P not found: $P in $DEGRAD_PARAMS_FILE"
    exit 1
fi

echo "$DEGRAD_LINE" > "$DEGRAD_OUTPUT"

###############################################################################
# EXTRACT OCCUPATION FACTORS
###############################################################################
awk -v p="$P" '

###############################################################################
# HEADER
###############################################################################
NR == 1 {

    for (i = 2; i <= NF; i++) {

        if ($i == p)
            target_col = i
    }

    if (target_col == 0) {

        print "ERROR: No column found for P=" p > "/dev/stderr"
        exit 1
    }

    next
}

###############################################################################
# DATA
###############################################################################
{

    op = $1
    val = $target_col

    printf "%-30s %.6f\n", op, val
}

' "$W_PARAMS_FILE" > "$EXTRA_OUTPUT"

###############################################################################
# INFO
###############################################################################
echo "========================================"
echo "Parameters generated successfully"
echo "========================================"
echo ""
echo "APP: $APP"
echo "P:   $P"
echo ""
echo "Degradation params -> $DEGRAD_OUTPUT"
echo "Occupation factors -> $EXTRA_OUTPUT"
echo ""
echo "Content degradation.txt:"
cat "$DEGRAD_OUTPUT"
echo ""
echo "Content extraoccupation.txt:"
cat "$EXTRA_OUTPUT"
