#! bin/bash.sh

app=$1
slots=$2
p=$3
req=$4
rate=$5

bash execute.sh $app $slots $p $req $rate && bash generate_sim_params.sh
