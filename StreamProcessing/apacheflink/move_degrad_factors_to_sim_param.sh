#!/bin/bash

###############################################################################
# movedegradp_factors_to_sim_param.sh
#
# Uso:
#
#   ./move_degrad_factors_to_sim_param.sh <app> <parallelism>
#
# Ejemplo:
#
#   ./move_degrad_factors_to_sim_param.sh q3 16
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
# ARCHIVO DE ENTRADA
###############################################################################
DEGRAD_PARAMS_FILE="load-sweep/degrad-params-${APP}.txt"

###############################################################################
# ARCHIVO DE SALIDA
###############################################################################
DEGRAD_OUTPUT="../input_data/degradation.txt"

###############################################################################
# VALIDAR ENTRADA
###############################################################################
if [ ! -f "$DEGRAD_PARAMS_FILE" ]; then
    echo "ERROR: no existe $DEGRAD_PARAMS_FILE"
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
echo ""
echo "Contenido degradation.txt:"
cat "$DEGRAD_OUTPUT"
echo ""
