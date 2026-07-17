#! bin/bash.sh

opername=$1

bash get_query.sh $(bash get_job_id.sh) | jq -r '.vertices[] | "\(.id);\(.name);"'  | tr -d '_[]: ' | tr '[:upper:]' '[:lower:]' | grep "$opername" | cut -d';' -f1
