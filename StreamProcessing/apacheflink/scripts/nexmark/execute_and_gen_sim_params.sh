#! bin/bash.sh

app=$1
slots=$2
p=$3
req=$4
rate=$5

## Get absolute path and locate.
DIR_BASE="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR_BASE" || exit 1

bash $DIR_BASE/execute.sh $app $slots $p $req $rate && bash $DIR_BASE/../common/generate_sim_params.sh nexmark
