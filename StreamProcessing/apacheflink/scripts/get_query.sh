#! bin/bash.sh


curl -s http://localhost:8081/jobs/$1 | jq 
