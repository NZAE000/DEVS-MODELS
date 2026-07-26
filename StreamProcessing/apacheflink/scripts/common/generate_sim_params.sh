#! bin/bash.sh

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

APP_PATH=$1

bash $DIR_BASE/extract_and_generate_operator_sim_params.sh && bash $DIR_BASE/../${APP_PATH}/generate_workload_sim_params.sh
