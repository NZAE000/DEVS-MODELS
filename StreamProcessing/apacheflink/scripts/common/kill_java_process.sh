#! bin/bash.sh

for pid in $(pgrep java); do kill -9  $pid; done
