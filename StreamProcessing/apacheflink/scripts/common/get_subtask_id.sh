#! bin/bash.sh

subtask_name=$1
# 1. Gets the absolute path of the folder where this script resides.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# 2. You position yourself in that base folder.
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/get_query.sh $(bash $DIR_BASE/get_job_id.sh) | jq -r '.vertices[] | "\(.id);\(.name);"'  | tr -d '_[]: ' | tr '[:upper:]' '[:lower:]' | grep "$subtask_name" | cut -d';' -f1
