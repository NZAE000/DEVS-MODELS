#! bin/bash.sh

q=$1

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/../../nexmark/bin/run_query.sh $q
