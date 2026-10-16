#! bin/bash.sh

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

FLINK_HOME="${FLINK_HOME:-$DIR_BASE/../../flink-2.2.0}"

bash $FLINK_HOME/bin/start-cluster.sh
