#! bin/bash.sh


kill -9 $(ss -tulpn | grep 9098 | cut -d ',' -f2 | cut -d '=' -f2)
