#!/bin/bash

###############################################################################
# generate_factor_params.sh
#
# Uso:
#
#   ./generate_factor_params.sh <app> <parallelism>
#
# Ejemplo:
#
#   ./generate_factor_params.sh q3 16
#
###############################################################################

set -e

###############################################################################
# VALIDACIÓN
###############################################################################
if [ $# -ne 2 ]; then
    echo "Uso: $0 <app> <parallelism>"
    exit 1
fi

APP="$1"
P="$2"

###############################################################################
# ARCHIVOS DE ENTRADA
###############################################################################
DEGRAD_PARAMS_FILE="load-sweep/degrad-params-${APP}.txt"
W_PARAMS_FILE="load-sweep/w-params-${APP}.txt"

###############################################################################
# ARCHIVOS DE SALIDA
###############################################################################
DEGRAD_OUTPUT="../input_data/degradation.txt"
EXTRA_OUTPUT="../input_data/extraoccupation.txt"

###############################################################################
# VALIDAR EXISTENCIA
###############################################################################
if [ ! -f "$DEGRAD_PARAMS_FILE" ]; then
    echo "ERROR: no existe $DEGRAD_PARAMS_FILE"
    exit 1
fi

if [ ! -f "$W_PARAMS_FILE" ]; then
    echo "ERROR: no existe $W_PARAMS_FILE"
    exit 1
fi

###############################################################################
# EXTRAER PARÁMETROS DE DEGRADACIÓN
###############################################################################
DEGRAD_LINE=$(awk -v p="$P" '
$1 == p {

    printf "%s %s %s %s %s\n",
           $2, $3, $4, $5, $6
}
' "$DEGRAD_PARAMS_FILE")

if [ -z "$DEGRAD_LINE" ]; then
    echo "ERROR: no se encontró P=$P en $DEGRAD_PARAMS_FILE"
    exit 1
fi

echo "$DEGRAD_LINE" > "$DEGRAD_OUTPUT"

###############################################################################
# EXTRAER FACTORES DE OCUPACIÓN
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

        print "ERROR: no se encontró columna para P=" p > "/dev/stderr"
        exit 1
    }

    next
}

###############################################################################
# DATOS
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
echo "Parámetros generados correctamente"
echo "========================================"
echo ""
echo "APP: $APP"
echo "P:   $P"
echo ""
echo "Degradation params -> $DEGRAD_OUTPUT"
echo "Occupation factors -> $EXTRA_OUTPUT"
echo ""
echo "Contenido degradation.txt:"
cat "$DEGRAD_OUTPUT"

echo ""
echo "Contenido extraoccupation.txt:"
cat "$EXTRA_OUTPUT"
