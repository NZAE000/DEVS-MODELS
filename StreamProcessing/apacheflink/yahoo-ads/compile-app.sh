#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${SCRIPT_DIR}"

mvn clean package \
    -pl flink-benchmarks \
    -am \
    -DskipTests \
    -Dflink.version=2.2.0 \
    -Dkafka.version=2.4.1 \
    -Dscala.binary.version=2.12