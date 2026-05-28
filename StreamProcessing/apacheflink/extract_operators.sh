#!/bin/bash
# ----------------------------------------------------------------------
# Extract operator features in 'operators/operators_list.txt' path with format:
# id;name;parallelism;next1-next2-..-nextN;ship_strategy
# ----------------------------------------------------------------------

FLINK_URL="http://localhost:8081"

echo "[INFO] Search active Job ID..."
JOB_ID=$(curl -s "${FLINK_URL}/jobs" | jq -r '.jobs[0].id')

if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
  echo "[ERROR] There are not actives or finished."
  exit 1
fi

echo "[INFO] Job ID found: $JOB_ID"

FOLDER="operators"
FILE="${FOLDER}/operators_list.txt"
PLAN_JSON="plan_tmp.json"

mkdir -p "$FOLDER"

# Get a job with a plan
curl -s "${FLINK_URL}/jobs/${JOB_ID}" > "$PLAN_JSON"

# ---------------------------------------------------------------------------------
# 1) Extract data from .vertices[] → ID, normalized name, parallelism
# ---------------------------------------------------------------------------------
echo "[INFO] Extracting vertices…"

declare -A NAME_BY_ID
declare -A PAR_BY_ID

normalize() {
    echo "$1" | tr -d '_[]: ' | tr '[:upper:]' '[:lower:]'
}

while IFS=';' read -r ID RAW_NAME PAR; do
    NAME=$(normalize "$RAW_NAME")
    NAME_BY_ID[$ID]="$NAME"
    PAR_BY_ID[$ID]="$PAR"
done < <(jq -r '.vertices[] | "\(.id);\(.name);\(.parallelism)"' "$PLAN_JSON")

# ---------------------------------------------------------------------------------
# 2) Extract links from .plan.nodes[] → successors + ship_strategy
# ---------------------------------------------------------------------------------

echo "[INFO] Processing plan to obtain topology…"

declare -A NEXTS_BY_ID
declare -A SHIP_BY_ID

NODES=$(jq -c '.plan.nodes[]' "$PLAN_JSON")

while read -r NODE; do
    TO_ID=$(echo "$NODE" | jq -r '.id')

    # Map of inputs (can be empty or null)
    MAP=$(echo "$NODE" | jq -c '.inputs // []')

    # Saltar nodos sin inputs
    if [ "$MAP" = "[]" ]; then
        continue
    fi

    while read -r EDGE; do
        # Validate that EDGE is not empty
        [[ -z "$EDGE" ]] && continue

        FROM_ID=$(echo "$EDGE" | jq -r '.id // "null"')
        STRAT=$(echo "$EDGE" | jq -r '.ship_strategy // "none"' | tr '[:upper:]' '[:lower:]')

        # Avoid FROM_ID null
        if [[ "$FROM_ID" == "null" ]]; then
            continue
        fi

        # Save successor
        if [[ -z "${NEXTS_BY_ID[$FROM_ID]}" ]]; then
            NEXTS_BY_ID[$FROM_ID]="$TO_ID"
        else
            NEXTS_BY_ID[$FROM_ID]="${NEXTS_BY_ID[$FROM_ID]}-$TO_ID"
        fi

        # Save the first ship_strategy
        if [[ -z "${SHIP_BY_ID[$FROM_ID]}" ]]; then
            SHIP_BY_ID[$FROM_ID]="$STRAT"
        fi

    done <<< "$(echo "$MAP" | jq -c '.[]')"

done <<< "$NODES"

# For nodes without successors
for ID in "${!NAME_BY_ID[@]}"; do
    if [[ -z "${NEXTS_BY_ID[$ID]}" ]]; then
        NEXTS_BY_ID[$ID]="0"
        SHIP_BY_ID[$ID]="none"
    fi
done

# ---------------------------------------------------------------------------------
# 3) Generate operators_list.txt
# ---------------------------------------------------------------------------------

echo "[INFO] Generating $FILE ..."
> "$FILE"

jq -r '.plan.nodes[].id' "$PLAN_JSON" | tac | while read -r ID; do
    NAME="${NAME_BY_ID[$ID]}"
    PAR="${PAR_BY_ID[$ID]}"
    NEXT="${NEXTS_BY_ID[$ID]}"
    SHIP="${SHIP_BY_ID[$ID]}"

    echo "${ID};${NAME};${PAR};${NEXT};${SHIP}" >> "$FILE"
done

echo "[SUCCESS] File generated"
echo ""

rm -f "$PLAN_JSON"
