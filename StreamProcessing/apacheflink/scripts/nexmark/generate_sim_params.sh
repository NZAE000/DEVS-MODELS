#! bin/bash.sh

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/../common/extract_operators.sh && bash $DIR_BASE/../common/extract_operator_metrics.sh && bash $DIR_BASE/../common/generate_operator_params.sh && bash $DIR_BASE/generate_workload_params.sh
