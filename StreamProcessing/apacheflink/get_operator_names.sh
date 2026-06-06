#! bin/bash.sh

bash get_query.sh $(bash get_job_id.sh) | jq -r '.vertices[] | "\(.name)"' | tr -d '_[]: ' | tr '[:upper:]' '[:lower:]'
