#! bin/bash.sh

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/get_query.sh $(bash  $DIR_BASE/get_job_id.sh) | jq -r '.vertices[] | "\(.name)"' | tr -d '_[]: ' | tr '[:upper:]' '[:lower:]'
