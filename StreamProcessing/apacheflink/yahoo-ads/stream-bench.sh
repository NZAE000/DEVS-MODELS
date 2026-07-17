#!/usr/bin/env bash
# Copyright 2015, Yahoo Inc.
# Licensed under the terms of the Apache License 2.0.
# Flink-only adaptation for the Yahoo Streaming Benchmark.
#
# Baseline stack:
#   - Apache Flink 1.11.0
#   - Apache Kafka 2.4.1
#   - ZooKeeper bundled with Kafka
#   - Redis 6.0.5
#
# Examples:
#   ./stream-bench-flink.sh SETUP
#   LOAD=100 TEST_TIME=30 ./stream-bench-flink.sh FLINK_TEST
#   ./stream-bench-flink.sh STOP_ALL
#
# To use an existing Flink installation:
#   USE_SYSTEM_FLINK=1 FLINK_HOME=/path/to/flink-1.11.0 \
#       ./stream-bench-flink.sh SETUP
#
# The existing Flink installation must be compatible with the benchmark JAR.
# For the first validation stage, use Flink 1.11.0.

set -Eeuo pipefail

###############################################################################
# Paths and configurable versions
###############################################################################

BENCHMARK_JAVA_HOME="${BENCHMARK_JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}"

if [[ ! -x "$BENCHMARK_JAVA_HOME/bin/java" ]]; then
    echo "ERROR: Java 11 not found at $BENCHMARK_JAVA_HOME" >&2
    exit 1
fi

export JAVA_HOME="$BENCHMARK_JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"

LEIN="${LEIN:-lein}"
MVN="${MVN:-mvn}"
MAKE="${MAKE:-make}"

KAFKA_VERSION="${KAFKA_VERSION:-2.4.1}"
REDIS_VERSION="${REDIS_VERSION:-6.0.5}"
FLINK_VERSION="${FLINK_VERSION:-1.11.0}"
SCALA_BIN_VERSION="${SCALA_BIN_VERSION:-2.12}"

KAFKA_DIR_NAME="${KAFKA_DIR_NAME:-kafka_${SCALA_BIN_VERSION}-${KAFKA_VERSION}}"
REDIS_DIR_NAME="${REDIS_DIR_NAME:-redis-${REDIS_VERSION}}"
FLINK_DIR_NAME="${FLINK_DIR_NAME:-flink-${FLINK_VERSION}}"

KAFKA_HOME="${KAFKA_HOME:-$ROOT/$KAFKA_DIR_NAME}"
REDIS_HOME="${REDIS_HOME:-$ROOT/$REDIS_DIR_NAME}"
#FLINK_HOME="${FLINK_HOME:-$ROOT/$FLINK_DIR_NAME}"

USE_SYSTEM_FLINK="${USE_SYSTEM_FLINK:-0}"
if [[ "$USE_SYSTEM_FLINK" == "1" ]]; then
    : "${FLINK_HOME:?Set FLINK_HOME when USE_SYSTEM_FLINK=1}"
    FLINK_HOME="$(cd "$FLINK_HOME" && pwd)"
else
    FLINK_HOME="$ROOT/$FLINK_DIR_NAME"
fi

APACHE_ARCHIVE="${APACHE_ARCHIVE:-https://archive.apache.org/dist}"
REDIS_DOWNLOAD_BASE="${REDIS_DOWNLOAD_BASE:-https://download.redis.io/releases}"

DOWNLOAD_CACHE="${DOWNLOAD_CACHE:-$ROOT/download-cache}"
RUN_DIR="${RUN_DIR:-$ROOT/run}"
LOG_DIR="${LOG_DIR:-$ROOT/logs/flink-benchmark}"

CONF_FILE="${CONF_FILE:-$ROOT/conf/localConf.yaml}"
BENCHMARK_CONF_FILE="${BENCHMARK_CONF_FILE:-$ROOT/conf/benchmarkConf.yaml}"

FLINK_JAR="${FLINK_JAR:-$ROOT/flink-benchmarks/target/flink-benchmarks-0.1.0.jar}"
FLINK_MAIN_CLASS="${FLINK_MAIN_CLASS:-flink.benchmark.AdvertisingTopologyNative}"

###############################################################################
# Benchmark configuration
###############################################################################

ZK_HOST="${ZK_HOST:-localhost}"
ZK_PORT="${ZK_PORT:-2181}"
KAFKA_HOST="${KAFKA_HOST:-localhost}"
KAFKA_PORT="${KAFKA_PORT:-9092}"
REDIS_HOST="${REDIS_HOST:-localhost}"

TOPIC="${TOPIC:-ad-events}"
PARTITIONS="${PARTITIONS:-1}"
LOAD="${LOAD:-1000}"
TEST_TIME="${TEST_TIME:-240}"

PROCESS_HOSTS="${PROCESS_HOSTS:-1}"
PROCESS_CORES="${PROCESS_CORES:-1}"

FLINK_BUFFER_TIMEOUT="${FLINK_BUFFER_TIMEOUT:-100}"
FLINK_CHECKPOINT_INTERVAL="${FLINK_CHECKPOINT_INTERVAL:-}"

ZOOKEEPER_CONFIG="${ZOOKEEPER_CONFIG:-$KAFKA_HOME/config/zookeeper.properties}"
KAFKA_CONFIG="${KAFKA_CONFIG:-$KAFKA_HOME/config/server.properties}"

mkdir -p "$DOWNLOAD_CACHE" "$RUN_DIR" "$LOG_DIR" "$(dirname "$CONF_FILE")"

###############################################################################
# Utility functions
###############################################################################

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

process_pids() {
    local pattern="$1"
    pgrep -f "$pattern" 2>/dev/null || true
}

is_running() {
    local pattern="$1"
    [[ -n "$(process_pids "$pattern")" ]]
}

wait_for_process() {
    local pattern="$1"
    local name="$2"
    local timeout="$3"
    local elapsed=0

    until is_running "$pattern"; do
        if (( elapsed >= timeout )); then
            die "$name did not start within ${timeout}s"
        fi
        sleep 1
        ((elapsed += 1))
    done
}

start_background_if_needed() {
    local pattern="$1"
    local name="$2"
    local timeout="$3"
    local logfile="$4"
    shift 4

    if is_running "$pattern"; then
        log "$name is already running"
        return
    fi

    log "Starting $name"
    nohup "$@" >"$logfile" 2>&1 &
    wait_for_process "$pattern" "$name" "$timeout"
}

stop_process_if_needed() {
    local pattern="$1"
    local name="$2"
    local timeout="${3:-10}"
    local pids

    pids="$(process_pids "$pattern")"
    if [[ -z "$pids" ]]; then
        log "No $name process found"
        return
    fi

    log "Stopping $name"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true

    local elapsed=0
    while is_running "$pattern" && (( elapsed < timeout )); do
        sleep 1
        ((elapsed += 1))
    done

    if is_running "$pattern"; then
        pids="$(process_pids "$pattern")"
        # shellcheck disable=SC2086
        kill -9 $pids 2>/dev/null || true
    fi
}

download_file() {
    local url="$1"
    local destination="$2"

    if [[ -s "$destination" ]]; then
        log "Using cached archive: $destination"
        return
    fi

    mkdir -p "$(dirname "$destination")"
    log "Downloading $url"

    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --retry 3 --output "$destination" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --tries=3 --output-document="$destination" "$url"
    else
        die "Install curl or wget to download dependencies"
    fi
}

fetch_and_extract() {
    local archive_name="$1"
    local url="$2"
    local expected_dir="$3"
    local archive="$DOWNLOAD_CACHE/$archive_name"

    if [[ -d "$expected_dir" ]]; then
        log "Using existing directory: $expected_dir"
        return
    fi

    download_file "$url" "$archive"
    log "Extracting $archive_name"
    tar -xzf "$archive" -C "$ROOT"

    [[ -d "$expected_dir" ]] ||
        die "Expected directory was not created: $expected_dir"
}

write_local_config() {
    cat >"$CONF_FILE" <<EOF
kafka.brokers:
  - "$KAFKA_HOST"

zookeeper.servers:
  - "$ZK_HOST"

kafka.port: $KAFKA_PORT
zookeeper.port: $ZK_PORT
redis.host: "$REDIS_HOST"
kafka.topic: "$TOPIC"
kafka.partitions: $PARTITIONS
process.hosts: $PROCESS_HOSTS
process.cores: $PROCESS_CORES
flink.buffer-timeout: $FLINK_BUFFER_TIMEOUT
EOF

    if [[ -n "$FLINK_CHECKPOINT_INTERVAL" ]]; then
        printf 'flink.checkpoint-interval: %s\n' \
            "$FLINK_CHECKPOINT_INTERVAL" >>"$CONF_FILE"
    fi

    log "Generated configuration: $CONF_FILE"
}

build_flink_modules() {
    require_command "$MVN"

    log "Building streaming-benchmark-common and flink-benchmarks"
    (
        cd "$ROOT"
        "$MVN" clean package \
            -pl flink-benchmarks \
            -am \
            -DskipTests \
            -Dflink.version="$FLINK_VERSION" \
            -Dkafka.version="$KAFKA_VERSION" \
            -Dscala.binary.version="$SCALA_BIN_VERSION"
    )

    [[ -f "$FLINK_JAR" ]] ||
        die "Flink benchmark JAR was not generated: $FLINK_JAR"
}

install_redis() {
    local archive_name="$REDIS_DIR_NAME.tar.gz"
    fetch_and_extract \
        "$archive_name" \
        "$REDIS_DOWNLOAD_BASE/$archive_name" \
        "$REDIS_HOME"

    require_command "$MAKE"
    log "Building Redis"
    "$MAKE" -C "$REDIS_HOME"
}

install_kafka() {
    local archive_name="$KAFKA_DIR_NAME.tgz"
    fetch_and_extract \
        "$archive_name" \
        "$APACHE_ARCHIVE/kafka/$KAFKA_VERSION/$archive_name" \
        "$KAFKA_HOME"
}

install_flink() {
    if [[ "$USE_SYSTEM_FLINK" == "1" ]]; then
        [[ -x "$FLINK_HOME/bin/flink" ]] ||
            die "Invalid FLINK_HOME: $FLINK_HOME"
        log "Using external Flink installation: $FLINK_HOME"
        return
    fi

    local archive_name="$FLINK_DIR_NAME-bin-scala_${SCALA_BIN_VERSION}.tgz"
    fetch_and_extract \
        "$archive_name" \
        "$APACHE_ARCHIVE/flink/flink-$FLINK_VERSION/$archive_name" \
        "$FLINK_HOME"
}

check_installation() {
    [[ -x "$KAFKA_HOME/bin/kafka-server-start.sh" ]] ||
        die "Kafka is not installed. Run SETUP first."
    [[ -x "$KAFKA_HOME/bin/zookeeper-server-start.sh" ]] ||
        die "ZooKeeper scripts are not available in Kafka."
    [[ -x "$REDIS_HOME/src/redis-server" ]] ||
        die "Redis is not installed. Run SETUP first."
    [[ -x "$FLINK_HOME/bin/flink" ]] ||
        die "Flink is not installed or FLINK_HOME is invalid."
}

create_kafka_topic() {
    local topics

    topics="$(
        "$KAFKA_HOME/bin/kafka-topics.sh" \
            --zookeeper "$ZK_HOST:$ZK_PORT" \
            --list
    )"

    if printf '%s\n' "$topics" | grep -Fxq "$TOPIC"; then
        log "Kafka topic '$TOPIC' already exists"
        return
    fi

    log "Creating Kafka topic '$TOPIC' with $PARTITIONS partition(s)"

    "$KAFKA_HOME/bin/kafka-topics.sh" \
        --zookeeper "$ZK_HOST:$ZK_PORT" \
        --create \
        --replication-factor 1 \
        --partitions "$PARTITIONS" \
        --topic "$TOPIC"
}

running_flink_job_id() {
    "$FLINK_HOME/bin/flink" list -r 2>/dev/null |
        grep -E 'Yahoo-Ads|Yahoo Advertising Benchmark|Flink Streaming Job' |
        grep -oE '[[:xdigit:]]{32}' |
        head -n 1 || true
}

###############################################################################
# Operations
###############################################################################

setup() {
    require_command java
    require_command "$LEIN"

    write_local_config
    build_flink_modules
    install_redis
    install_kafka
    install_flink

    log "SETUP completed"
    log "Flink home: $FLINK_HOME"
    log "Benchmark JAR: $FLINK_JAR"
}

start_zookeeper() {
    check_installation
    start_background_if_needed \
        'org.apache.zookeeper.server.quorum.QuorumPeerMain' \
        'ZooKeeper' \
        15 \
        "$LOG_DIR/zookeeper.log" \
        "$KAFKA_HOME/bin/zookeeper-server-start.sh" \
        "$ZOOKEEPER_CONFIG"
}

stop_zookeeper() {
    if [[ -x "$KAFKA_HOME/bin/zookeeper-server-stop.sh" ]]; then
        "$KAFKA_HOME/bin/zookeeper-server-stop.sh" >/dev/null 2>&1 || true
    fi
    stop_process_if_needed \
        'org.apache.zookeeper.server.quorum.QuorumPeerMain' \
        'ZooKeeper'
    rm -rf /tmp/zookeeper
}

start_redis() {
    check_installation

    start_background_if_needed \
        "$REDIS_HOME/src/redis-server" \
        'Redis' \
        10 \
        "$LOG_DIR/redis.log" \
        "$REDIS_HOME/src/redis-server" \
        --bind 127.0.0.1 \
        --port 6379 \
        --dir "$RUN_DIR"

    [[ -f "$BENCHMARK_CONF_FILE" ]] ||
        die "Redis initialization config not found: $BENCHMARK_CONF_FILE"

    log "Initializing benchmark campaign data in Redis"
    (
        cd "$ROOT/data"
        "$LEIN" run -n --configPath "$BENCHMARK_CONF_FILE"
    )
}

stop_redis() {
    if command -v redis-cli >/dev/null 2>&1; then
        redis-cli -h "$REDIS_HOST" -p 6379 shutdown nosave \
            >/dev/null 2>&1 || true
    fi

    stop_process_if_needed "$REDIS_HOME/src/redis-server" 'Redis'
    rm -f "$RUN_DIR/dump.rdb"
}

start_kafka() {
    check_installation

    is_running 'org.apache.zookeeper.server.quorum.QuorumPeerMain' ||
        die "ZooKeeper must be running before Kafka"

    start_background_if_needed \
      'kafka\.Kafka' \
      'Kafka' \
      20 \
      "$LOG_DIR/kafka.log" \
      "$KAFKA_HOME/bin/kafka-server-start.sh" \
      "$KAFKA_CONFIG"

    wait_for_kafka 30
    create_kafka_topic
}

stop_kafka() {
    if [[ -x "$KAFKA_HOME/bin/kafka-server-stop.sh" ]]; then
        "$KAFKA_HOME/bin/kafka-server-stop.sh" >/dev/null 2>&1 || true
    fi

    stop_process_if_needed 'kafka\.Kafka' 'Kafka'
    rm -rf /tmp/kafka-logs
}

wait_for_kafka() {
    local timeout="${1:-30}"
    local elapsed=0

    log "Waiting for Kafka broker"

    until "$KAFKA_HOME/bin/kafka-broker-api-versions.sh" \
        --bootstrap-server "$KAFKA_HOST:$KAFKA_PORT" \
        >/dev/null 2>&1
    do
        if (( elapsed >= timeout )); then
            die "Kafka broker was not ready within ${timeout}s"
        fi

        sleep 1
        ((elapsed += 1))
    done

    log "Kafka broker is ready"
}

start_flink() {
    check_installation

    if is_running 'org.apache.flink.runtime.entrypoint.StandaloneSessionClusterEntrypoint|org.apache.flink.runtime.jobmanager.JobManager'; then
        log "Flink cluster is already running"
        return
    fi

    log "Starting Flink cluster"
    "$FLINK_HOME/bin/start-cluster.sh"
    sleep 3

    if ! is_running 'org.apache.flink.runtime.entrypoint.StandaloneSessionClusterEntrypoint|org.apache.flink.runtime.jobmanager.JobManager'; then
        die "Flink cluster did not start. Check $FLINK_HOME/log"
    fi
}

stop_flink() {
    if [[ -x "$FLINK_HOME/bin/stop-cluster.sh" ]]; then
        log "Stopping Flink cluster"
        "$FLINK_HOME/bin/stop-cluster.sh" || true
    else
        log "No Flink stop script found"
    fi
}

start_flink_processing() {
    check_installation
    [[ -f "$FLINK_JAR" ]] ||
        die "Benchmark JAR not found: $FLINK_JAR"

    if [[ -n "$(running_flink_job_id)" ]]; then
        log "Yahoo Flink benchmark job is already running"
        return
    fi

    log "Submitting Yahoo Advertising Benchmark to Flink"
    "$FLINK_HOME/bin/flink" run \
        --detached \
        -c "$FLINK_MAIN_CLASS" \
        "$FLINK_JAR" \
        --confPath "$CONF_FILE"

    sleep 3

    local job_id
    job_id="$(running_flink_job_id)"
    [[ -n "$job_id" ]] ||
        die "Flink benchmark job was not found after submission"

    printf '%s\n' "$job_id" >"$RUN_DIR/flink-job.id"
    log "Flink benchmark job ID: $job_id"
}

stop_flink_processing() {
    local job_id=""

    if [[ -f "$RUN_DIR/flink-job.id" ]]; then
        job_id="$(<"$RUN_DIR/flink-job.id")"
    fi

    if [[ -z "$job_id" ]]; then
        job_id="$(running_flink_job_id)"
    fi

    if [[ -z "$job_id" ]]; then
        log "No running Yahoo Flink benchmark job found"
        rm -f "$RUN_DIR/flink-job.id"
        return
    fi

    log "Cancelling Flink job $job_id"
    "$FLINK_HOME/bin/flink" cancel "$job_id" || true
    rm -f "$RUN_DIR/flink-job.id"
    sleep 3
}

start_load() {
    [[ -f "$CONF_FILE" ]] ||
        die "Configuration file not found: $CONF_FILE"

    if is_running 'leiningen\.core\.main.* -r '; then
        log "Load generator is already running"
        return
    fi

    log "Starting load generator at $LOAD event(s)/s"
    (
        cd "$ROOT/data"
        nohup "$LEIN" run -r -t "$LOAD" \
            --configPath "$CONF_FILE" \
            >"$LOG_DIR/load-generator.log" 2>&1 &
        echo $! >"$RUN_DIR/load-generator.pid"
    )

    sleep 2
}

stop_load() {
    if [[ -f "$RUN_DIR/load-generator.pid" ]]; then
        local pid
        pid="$(<"$RUN_DIR/load-generator.pid")"
        if kill -0 "$pid" 2>/dev/null; then
            log "Stopping load generator"
            kill "$pid" 2>/dev/null || true
            sleep 1
        fi
        rm -f "$RUN_DIR/load-generator.pid"
    fi

    stop_process_if_needed 'leiningen\.core\.main.* -r ' 'Load generator'

    if [[ -d "$ROOT/data" && -f "$CONF_FILE" ]]; then
        log "Generating benchmark result files"
        (
            cd "$ROOT/data"
            "$LEIN" run -g --configPath "$CONF_FILE" || true
        )
    fi
}

stop_all() {
    set +e
    stop_load
    stop_flink_processing
    stop_flink
    stop_kafka
    stop_redis
    stop_zookeeper
    set -e
}

flink_test() {
    local completed=0

    cleanup_test() {
        local status=$?
        if [[ "$completed" != "1" ]]; then
            log "Test interrupted or failed; stopping all services"
            stop_all
        fi
        return "$status"
    }

    trap cleanup_test EXIT INT TERM

    start_zookeeper
    start_redis
    start_kafka
    start_flink
    start_flink_processing
    start_load

    log "Benchmark running for $TEST_TIME second(s)"
    sleep "$TEST_TIME"

    stop_load
    stop_flink_processing
    stop_flink
    stop_kafka
    stop_redis
    stop_zookeeper

    completed=1
    trap - EXIT INT TERM
    log "FLINK_TEST completed"
}

print_help() {
    cat <<EOF
Yahoo Streaming Benchmark - Flink-only runner

Usage:
  $0 OPERATION [OPERATION ...]

Operations:
  SETUP                    Build Flink modules and install Redis, Kafka, and
                           Flink $FLINK_VERSION (unless USE_SYSTEM_FLINK=1).
  START_ZK                 Start ZooKeeper bundled with Kafka.
  STOP_ZK                  Stop ZooKeeper.
  START_REDIS              Start Redis and initialize campaign data.
  STOP_REDIS               Stop Redis.
  START_KAFKA              Start Kafka and create the benchmark topic.
  STOP_KAFKA               Stop Kafka.
  START_FLINK              Start the standalone Flink cluster.
  STOP_FLINK               Stop the standalone Flink cluster.
  START_FLINK_PROCESSING   Submit AdvertisingTopologyNative.
  STOP_FLINK_PROCESSING    Cancel the benchmark Flink job.
  START_LOAD               Start the Kafka load generator.
  STOP_LOAD                Stop the load generator and generate result files.
  FLINK_TEST               Run the complete benchmark workflow.
  STOP_ALL                 Stop all benchmark processes.
  HELP                     Show this message.

Frequently used environment variables:
  LOAD=$LOAD
  TEST_TIME=$TEST_TIME
  PARTITIONS=$PARTITIONS
  PROCESS_HOSTS=$PROCESS_HOSTS
  PROCESS_CORES=$PROCESS_CORES
  TOPIC=$TOPIC
  FLINK_VERSION=$FLINK_VERSION
  USE_SYSTEM_FLINK=$USE_SYSTEM_FLINK
  FLINK_HOME=$FLINK_HOME

Examples:
  $0 SETUP
  LOAD=100 TEST_TIME=30 $0 FLINK_TEST
  PARTITIONS=8 PROCESS_CORES=8 LOAD=10000 TEST_TIME=240 \
      $0 SETUP FLINK_TEST

Important:
  - For effective source parallelism P, use PARTITIONS >= PROCESS_HOSTS*PROCESS_CORES.
  - The first validation stage should use Flink 1.11.0.
EOF
}

run() {
    local operation="${1:-HELP}"

    case "$operation" in
        SETUP)                  setup ;;
        START_ZK)               start_zookeeper ;;
        STOP_ZK)                stop_zookeeper ;;
        START_REDIS)            start_redis ;;
        STOP_REDIS)             stop_redis ;;
        START_KAFKA)            start_kafka ;;
        STOP_KAFKA)             stop_kafka ;;
        START_FLINK)            start_flink ;;
        STOP_FLINK)             stop_flink ;;
        START_FLINK_PROCESSING) start_flink_processing ;;
        STOP_FLINK_PROCESSING)  stop_flink_processing ;;
        START_LOAD)             start_load ;;
        STOP_LOAD)              stop_load ;;
        FLINK_TEST)             flink_test ;;
        STOP_ALL)               stop_all ;;
        HELP|-h|--help)         print_help ;;
        *)
            print_help
            die "Unknown operation: $operation"
            ;;
    esac
}

if (( $# == 0 )); then
    print_help
    exit 1
fi

while (( $# > 0 )); do
    run "$1"
    shift
done