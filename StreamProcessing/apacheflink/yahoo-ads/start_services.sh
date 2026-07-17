#!bin/bash.sh

./stream-bench.sh START_ZK
./stream-bench.sh START_REDIS
./stream-bench.sh START_KAFKA
./stream-bench.sh START_FLINK
./stream-bench.sh START_FLINK_PROCESSING
