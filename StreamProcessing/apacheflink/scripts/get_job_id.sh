#! bin/bash.sh


job=$(curl -s http://localhost:8081/jobs | jq | grep "id" | cut -d'"' -f4)
echo "$job"
