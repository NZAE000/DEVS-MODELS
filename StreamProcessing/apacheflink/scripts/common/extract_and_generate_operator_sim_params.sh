#! bin/bash.sh

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/extract_subtasks.sh && bash $DIR_BASE/extract_operator_metrics.sh && bash $DIR_BASE/generate_operator_sim_params.sh