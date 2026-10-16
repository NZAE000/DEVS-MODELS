#!/usr/bin/env bash
# Copyright 2015, Yahoo Inc.
# Licensed under the terms of the Apache License 2.0.
# Flink-only adaptation for the Yahoo Streaming Benchmark.
#
# Shared-services layout:
#   <services-root>/
#   ├── flink-2.2.0/
#   ├── kafka_2.12-2.4.1/
#   ├── redis-6.0.5/
#   ├── download-cache/
#   ├── nexmark/
#   └── yahoo-ads/
#
# Defaults:
#   PROJECT_ROOT  = directory containing this script
#   SERVICES_ROOT = parent directory of PROJECT_ROOT
#   FLINK_HOME    = $SERVICES_ROOT/flink-2.2.0

set -Eeuo pipefail

###############################################################################
# Project, shared services, and Java
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$SCRIPT_DIR}"
SERVICES_ROOT="${SERVICES_ROOT:-$(cd "$PROJECT_ROOT/.." && pwd)}"
COMMON_DIR="$SERVICES_ROOT/scripts/common"
readonly COMMON_DIR

BENCHMARK_JAVA_HOME="${BENCHMARK_JAVA_HOME:-${JAVA_HOME:-}}"
if [[ -n "$BENCHMARK_JAVA_HOME" ]]; then
    if [[ ! -x "$BENCHMARK_JAVA_HOME/bin/java" ]]; then
        echo "ERROR: Invalid Java installation: $BENCHMARK_JAVA_HOME" >&2
        exit 1
    fi
    export JAVA_HOME="$BENCHMARK_JAVA_HOME"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

###############################################################################
# Tools and configurable versions
###############################################################################

LEIN="${LEIN:-lein}"
MVN="${MVN:-mvn}"
MAKE="${MAKE:-make}"

KAFKA_VERSION="${KAFKA_VERSION:-2.4.1}"
REDIS_VERSION="${REDIS_VERSION:-6.0.5}"
FLINK_VERSION="${FLINK_VERSION:-2.2.0}"
SCALA_BIN_VERSION="${SCALA_BIN_VERSION:-2.12}"

KAFKA_DIR_NAME="${KAFKA_DIR_NAME:-kafka_${SCALA_BIN_VERSION}-${KAFKA_VERSION}}"
REDIS_DIR_NAME="${REDIS_DIR_NAME:-redis-${REDIS_VERSION}}"
FLINK_DIR_NAME="${FLINK_DIR_NAME:-flink-${FLINK_VERSION}}"

KAFKA_HOME="${KAFKA_HOME:-$SERVICES_ROOT/$KAFKA_DIR_NAME}"
REDIS_HOME="${REDIS_HOME:-$SERVICES_ROOT/$REDIS_DIR_NAME}"
FLINK_HOME="${FLINK_HOME:-$SERVICES_ROOT/$FLINK_DIR_NAME}"

APACHE_ARCHIVE="${APACHE_ARCHIVE:-https://archive.apache.org/dist}"
REDIS_DOWNLOAD_BASE="${REDIS_DOWNLOAD_BASE:-https://download.redis.io/releases}"

DOWNLOAD_CACHE="${DOWNLOAD_CACHE:-$SERVICES_ROOT/download-cache}"
RUN_DIR="${RUN_DIR:-$PROJECT_ROOT/run}"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs/flink-benchmark}"

FLINK_JAR="${FLINK_JAR:-$PROJECT_ROOT/flink-benchmarks/target/flink-benchmarks-0.1.0.jar}"
FLINK_MAIN_CLASS="${FLINK_MAIN_CLASS:-flink.benchmark.AdvertisingTopologyNative}"

CONF_FILE="${CONF_FILE:-$PROJECT_ROOT/conf/localConf.yaml}"
BENCHMARK_CONF_FILE="${BENCHMARK_CONF_FILE:-$PROJECT_ROOT/conf/benchmarkConf.yaml}"
WORKLOADS_FILE="${WORKLOADS_FILE:-$PROJECT_ROOT/conf/workloadbyreq.txt}"
DRAIN_SECONDS="${DRAIN_SECONDS:-30}"
FLINK_REST_URL="${FLINK_REST_URL:-http://localhost:8081}"
DRAIN_POLL_SECONDS="${DRAIN_POLL_SECONDS:-1}"
DRAIN_STABLE_POLLS="${DRAIN_STABLE_POLLS:-5}"
DRAIN_TIMEOUT_SECONDS="${DRAIN_TIMEOUT_SECONDS:-900}"
SAVEPOINT_DIR="${SAVEPOINT_DIR:-/tmp/yahoo-flink-savepoints}"

MAX_SPEED="${MAX_SPEED:-false}"
FIXED_PAYLOAD="${FIXED_PAYLOAD:-false}"
PAYLOAD_POOL="${PAYLOAD_POOL:-true}"
PAYLOAD_POOL_SIZE="${PAYLOAD_POOL_SIZE:-65536}"

if [[ "${FIXED_PAYLOAD,,}" == "true" &&
      "${PAYLOAD_POOL,,}" == "true" ]]; then
    die "FIXED_PAYLOAD and PAYLOAD_POOL cannot both be enabled"
fi

if ! [[ "$PAYLOAD_POOL_SIZE" =~ ^[1-9][0-9]*$ ]]; then
    die "PAYLOAD_POOL_SIZE must be a positive integer: $PAYLOAD_POOL_SIZE"
fi

###############################################################################
# Benchmark configuration
###############################################################################

ZK_HOST="${ZK_HOST:-localhost}"
ZK_PORT="${ZK_PORT:-2181}"
KAFKA_HOST="${KAFKA_HOST:-localhost}"
KAFKA_PORT="${KAFKA_PORT:-9092}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

TOPIC="${TOPIC:-ad-events}"
PARTITIONS="${PARTITIONS:-1}"
LOAD="${LOAD:-1000}"
TEST_TIME="${TEST_TIME:-240}"

PROCESS_HOSTS="${PROCESS_HOSTS:-1}"
PROCESS_CORES="${PROCESS_CORES:-1}"

DEFAULT_PARALLELISM=$((PROCESS_HOSTS * PROCESS_CORES))

if (( DEFAULT_PARALLELISM < PARTITIONS )); then
    DEFAULT_SOURCE_PARALLELISM="$DEFAULT_PARALLELISM"
else
    DEFAULT_SOURCE_PARALLELISM="$PARTITIONS"
fi

PARALLELISM_SOURCE="${PARALLELISM_SOURCE:-$DEFAULT_SOURCE_PARALLELISM}"
PARALLELISM_DESERIALIZE="${PARALLELISM_DESERIALIZE:-$DEFAULT_PARALLELISM}"
PARALLELISM_FILTER="${PARALLELISM_FILTER:-$DEFAULT_PARALLELISM}"
PARALLELISM_PROJECT="${PARALLELISM_PROJECT:-$DEFAULT_PARALLELISM}"
PARALLELISM_REDIS_JOIN="${PARALLELISM_REDIS_JOIN:-$DEFAULT_PARALLELISM}"
PARALLELISM_CAMPAIGN_PROCESSOR="${PARALLELISM_CAMPAIGN_PROCESSOR:-$DEFAULT_PARALLELISM}"

FLINK_BUFFER_TIMEOUT="${FLINK_BUFFER_TIMEOUT:-100}"
FLINK_CHECKPOINT_INTERVAL="${FLINK_CHECKPOINT_INTERVAL:-}"

ZOOKEEPER_CONFIG="${ZOOKEEPER_CONFIG:-$KAFKA_HOME/config/zookeeper.properties}"
KAFKA_CONFIG="${KAFKA_CONFIG:-$KAFKA_HOME/config/server.properties}"

mkdir -p "$SERVICES_ROOT" "$DOWNLOAD_CACHE" "$RUN_DIR" "$LOG_DIR" "$(dirname "$CONF_FILE")"

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
    log "Extracting $archive_name into $SERVICES_ROOT"
    tar -xzf "$archive" -C "$SERVICES_ROOT"

    [[ -d "$expected_dir" ]] || die "Expected directory was not created: $expected_dir"
}

write_local_config() {
    (( PARALLELISM_SOURCE > 0 )) || die "PARALLELISM_SOURCE must be greater than zero"

    (( PARALLELISM_SOURCE <= PARTITIONS )) || die "PARALLELISM_SOURCE cannot exceed PARTITIONS"

    cat >"$CONF_FILE" <<EOF_CONF
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

parallelism.source: $PARALLELISM_SOURCE
parallelism.deserialize: $PARALLELISM_DESERIALIZE
parallelism.filter: $PARALLELISM_FILTER
parallelism.project: $PARALLELISM_PROJECT
parallelism.redis-join: $PARALLELISM_REDIS_JOIN
parallelism.campaign-processor: $PARALLELISM_CAMPAIGN_PROCESSOR

flink.buffer-timeout: $FLINK_BUFFER_TIMEOUT
EOF_CONF

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
        cd "$PROJECT_ROOT"
        "$MVN" clean package \
            -pl flink-benchmarks \
            -am \
            -DskipTests \
            -Dflink.version="$FLINK_VERSION" \
            -Dkafka.version="$KAFKA_VERSION" \
            -Dscala.binary.version="$SCALA_BIN_VERSION"
    )

    [[ -f "$FLINK_JAR" ]] || die "Flink benchmark JAR was not generated: $FLINK_JAR"
}

install_redis() {
    local archive_name="$REDIS_DIR_NAME.tar.gz"
    fetch_and_extract "$archive_name" "$REDIS_DOWNLOAD_BASE/$archive_name" "$REDIS_HOME"
    require_command "$MAKE"
    log "Building Redis"
    "$MAKE" -C "$REDIS_HOME"
}

install_kafka() {
    local archive_name="$KAFKA_DIR_NAME.tgz"
    fetch_and_extract "$archive_name" "$APACHE_ARCHIVE/kafka/$KAFKA_VERSION/$archive_name" "$KAFKA_HOME"
}

check_shared_flink() {
    [[ -x "$FLINK_HOME/bin/flink" ]] || die "Shared Flink installation not found at: $FLINK_HOME"
    log "Using shared Flink installation: $FLINK_HOME"
    "$FLINK_HOME/bin/flink" --version
}

check_installation() {
    [[ -x "$KAFKA_HOME/bin/kafka-server-start.sh" ]] || die "Kafka is not installed at $KAFKA_HOME. Run SETUP first."
    [[ -x "$KAFKA_HOME/bin/zookeeper-server-start.sh" ]] || die "ZooKeeper scripts are not available in $KAFKA_HOME."
    [[ -x "$REDIS_HOME/src/redis-server" ]] || die "Redis is not installed at $REDIS_HOME. Run SETUP first."
    [[ -x "$FLINK_HOME/bin/flink" ]] || die "Shared Flink installation is invalid: $FLINK_HOME"
}

create_kafka_topic() {
    local topics
    topics="$("$KAFKA_HOME/bin/kafka-topics.sh" --zookeeper "$ZK_HOST:$ZK_PORT" --list)"

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
    check_shared_flink

    log "SETUP completed"
    log "Project root: $PROJECT_ROOT"
    log "Services root: $SERVICES_ROOT"
    log "Java home: ${JAVA_HOME:-<not explicitly set>}"
    log "Flink version: $FLINK_VERSION"
    log "Flink home: $FLINK_HOME"
    log "Kafka home: $KAFKA_HOME"
    log "Redis home: $REDIS_HOME"
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
    stop_process_if_needed 'org.apache.zookeeper.server.quorum.QuorumPeerMain' 'ZooKeeper'
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
        --port "$REDIS_PORT" \
        --dir "$RUN_DIR"

    [[ -f "$BENCHMARK_CONF_FILE" ]] || die "Redis initialization config not found: $BENCHMARK_CONF_FILE"

    log "Initializing benchmark campaign data in Redis"
    (
        cd "$PROJECT_ROOT/data"
        "$LEIN" run -n --configPath "$BENCHMARK_CONF_FILE"
    )
}

stop_redis() {
    if [[ -x "$REDIS_HOME/src/redis-cli" ]]; then
        "$REDIS_HOME/src/redis-cli" -h "$REDIS_HOST" -p "$REDIS_PORT" shutdown nosave >/dev/null 2>&1 || true
    elif command -v redis-cli >/dev/null 2>&1; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" shutdown nosave >/dev/null 2>&1 || true
    fi

    stop_process_if_needed "$REDIS_HOME/src/redis-server" 'Redis'
    rm -f "$RUN_DIR/dump.rdb"
}

wait_for_kafka() {
    local timeout="${1:-30}"
    local elapsed=0

    log "Waiting for Kafka broker"
    until "$KAFKA_HOME/bin/kafka-broker-api-versions.sh" \
        --bootstrap-server "$KAFKA_HOST:$KAFKA_PORT" >/dev/null 2>&1
    do
        if (( elapsed >= timeout )); then
            die "Kafka broker was not ready within ${timeout}s"
        fi
        sleep 1
        ((elapsed += 1))
    done
    log "Kafka broker is ready"
}

start_kafka() {
    check_installation
    is_running 'org.apache.zookeeper.server.quorum.QuorumPeerMain' || die "ZooKeeper must be running before Kafka"

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

start_flink() {
    check_installation

    if is_running 'org.apache.flink.runtime.entrypoint.StandaloneSessionClusterEntrypoint|org.apache.flink.runtime.jobmanager.JobManager'; then
        log "Flink cluster is already running"
        return
    fi

    log "Starting shared Flink cluster"
    "$FLINK_HOME/bin/start-cluster.sh"
    sleep 3

    if ! is_running 'org.apache.flink.runtime.entrypoint.StandaloneSessionClusterEntrypoint|org.apache.flink.runtime.jobmanager.JobManager'; then
        die "Flink cluster did not start. Check $FLINK_HOME/log"
    fi
}

stop_flink() {
    if [[ -x "$FLINK_HOME/bin/stop-cluster.sh" ]]; then
        log "Stopping shared Flink cluster"
        "$FLINK_HOME/bin/stop-cluster.sh" || true
    else
        log "No Flink stop script found at $FLINK_HOME"
    fi
}

start_flink_processing() {
    check_installation
    [[ -f "$FLINK_JAR" ]] || die "Benchmark JAR not found: $FLINK_JAR"

    is_running "$REDIS_HOME/src/redis-server" || die "Redis is not running. Execute START_REDIS first."
    is_running 'kafka\.Kafka' || die "Kafka is not running. Execute START_KAFKA first."
    is_running 'org.apache.flink.runtime.entrypoint.StandaloneSessionClusterEntrypoint|org.apache.flink.runtime.jobmanager.JobManager' || die "Flink is not running. Execute START_FLINK first."

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
    [[ -n "$job_id" ]] || die "Flink benchmark job was not found after submission"

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

get_yahoo_job_id() {
    [[ -f "$RUN_DIR/flink-job.id" ]] ||
        die "Flink job ID file not found"

    local job_id
    job_id="$(<"$RUN_DIR/flink-job.id")"

    [[ -n "$job_id" ]] ||
        die "Empty Flink job ID"

    printf '%s\n' "$job_id"
}

get_acc_metric_sum() {
    local job_id=$1
    local subtask_name=$2
    local metric_name=$3

    local response="[]"
    local value=""
    local attempt

    local -r max_attempts=10
    local -r retry_sleep=0.5

    for ((attempt = 1; attempt <= max_attempts; attempt++))
    do
        response="$(
            JOB_ID_OVERRIDE="$job_id" \
            RAW_OUTPUT=true \
            bash "$COMMON_DIR/get_subtask_metrics_acc.sh" \
                "$subtask_name" \
                "$metric_name" \
                "sum" \
            2>/dev/null || printf '[]'
        )"

        value="$(
            jq -r \
                --arg metric "$metric_name" '
                    [
                        .[]
                        | select(.id == $metric)
                        | .sum
                    ][0] // empty
                ' <<< "$response" \
            2>/dev/null || true
        )"

        if [[ -n "$value" && "$value" != "null" ]]; then
            printf '%s\n' "$value"
            return 0
        fi

        echo \
            "[DEBUG] Metric $metric_name for $subtask_name unavailable " \
            "(attempt $attempt/$max_attempts): $response" \
            >&2

        sleep "$retry_sleep"
    done

    echo \
        "[ERROR] Metric '$metric_name' for '$subtask_name' unavailable after $max_attempts attempts" \
        >&2

    printf 'NA\n'
}

get_downstream_signature() {
    local job_id=$1

    local operator
    local records_in
    local records_out
    local busy_ms

    local -a operators=(
        "deserialize"
        "filterviews"
        "projectevent"
        "rediscampaignjoin"
        "campaignprocessor"
    )

    for operator in "${operators[@]}"
    do
        records_in="$(
            get_acc_metric_sum \
                "$job_id" \
                "$operator" \
                "numRecordsIn"
        )"

        records_out="$(
            get_acc_metric_sum \
                "$job_id" \
                "$operator" \
                "numRecordsOut"
        )"

        busy_ms="$(
            get_acc_metric_sum \
                "$job_id" \
                "$operator" \
                "exactAccumulateBusyTimeMs"
        )"

        if [[ "$records_in" == "NA" ||
              "$records_out" == "NA" ||
              "$busy_ms" == "NA" ]]; then

            echo \
                "[WARN] Incomplete downstream metrics for $operator" \
                >&2

            return 1
        fi

        printf '%s|%s|%s|%s\n' \
            "$operator" \
            "$records_in" \
            "$records_out" \
            "$busy_ms"
    done
}

wait_pipeline_drain() {
    local job_id
    job_id="$(get_yahoo_job_id)"

    local expected_events
    expected_events="$(get_expected_event_count)"

    log "Waiting for pipeline drain"
    log "Expected source records: $expected_events"
    log "Drain stability requirement: $DRAIN_STABLE_POLLS poll(s)"

    local start_wait
    start_wait="$(date +%s)"

    local source_records
    local stable_polls=0

    local previous_signature=""
    local current_signature=""

    local stable_candidate_ms=""

    while true
    do
        local now
        now="$(date +%s)"

        if (( now - start_wait > DRAIN_TIMEOUT_SECONDS )); then
            die \
                "Pipeline drain timeout after ${DRAIN_TIMEOUT_SECONDS}s"
        fi

        #
        # Job must remain RUNNING while we measure the drain.
        #
        local state
        state="$(
            curl -fsS \
                "$FLINK_REST_URL/jobs/$job_id" |
            jq -r '.state // empty'
        )"

        [[ "$state" == "RUNNING" ]] ||
            die \
                "Yahoo Flink job is no longer RUNNING: $state"

        #
        # Aggregate Kafka Source output across all source subtasks.
        #
        source_records="$(
            get_acc_metric_sum \
                "$job_id" \
                "sourcekafkasource" \
                "numRecordsOut"
        )"

        if [[ "$source_records" == "NA" ]]; then
            die \
                "Kafka Source numRecordsOut could not be retrieved after retries"
        fi

        source_records="$(
            awk \
                -v value="$source_records" \
                'BEGIN { printf "%.0f", value }'
        )"

        log \
            "Drain check: source=$source_records/$expected_events stable=$stable_polls/$DRAIN_STABLE_POLLS"

        #
        # Kafka Source has not emitted all expected records yet.
        #
        if (( source_records < expected_events )); then
            stable_polls=0
            previous_signature=""

            sleep "$DRAIN_POLL_SECONDS"
            continue
        fi

        #
        # This would indicate contamination of the Kafka topic or another
        # producer writing into it.
        #
        if (( source_records > expected_events )); then
            die \
                "Kafka Source consumed more records than expected: $source_records > $expected_events"
        fi

        #
        # All expected records have crossed Kafka Source.
        # Now detect downstream quiescence.
        #
        if ! current_signature="$(
            get_downstream_signature "$job_id"
        )"; then
            log \
                "Downstream metrics temporarily unavailable; retrying"

            stable_polls=0
            previous_signature=""

            sleep "$DRAIN_POLL_SECONDS"
            continue
        fi

        if [[ -n "$previous_signature" &&
            "$current_signature" == "$previous_signature" ]]; then

            stable_polls=$((stable_polls + 1))

        else
            #
            # A new downstream state was observed.
            # This timestamp becomes the candidate drain completion time.
            #
            stable_polls=0
            stable_candidate_ms="$(date +%s%3N)"
        fi

        previous_signature="$current_signature"

        log \
            "Downstream stability: $stable_polls/$DRAIN_STABLE_POLLS"

        if (( stable_polls >= DRAIN_STABLE_POLLS )); then
            #
            # The current signature has now been confirmed stable.
            # Use the timestamp at which this final signature was first observed,
            # not the later confirmation timestamp.
            #
            PIPELINE_DRAINED_MS="$stable_candidate_ms"
            export PIPELINE_DRAINED_MS

            printf '%s\n' \
                "$PIPELINE_DRAINED_MS" \
                >"$RUN_DIR/pipeline-drained.ms"

            local confirmation_ms
            confirmation_ms="$(date +%s%3N)"

            log \
                "Pipeline drain confirmed at $confirmation_ms ms"

            log \
                "Estimated pipeline completion at $PIPELINE_DRAINED_MS ms"

            break
        fi

        sleep "$DRAIN_POLL_SECONDS"
    done
}

write_dynamic_experiment_summary() {
    local stage_file="$PROJECT_ROOT/data/dynamic-load-stages.tsv"

    [[ -f "$stage_file" ]] ||
        die "Dynamic stage file not found: $stage_file"

    [[ -f "$RUN_DIR/pipeline-drained.ms" ]] ||
        die "Pipeline drain timestamp not found"

    local experiment_start_ms
    experiment_start_ms="$(
        awk -F'\t' '
            NR == 2 {
                print $4
                exit
            }
        ' "$stage_file"
    )"

    local emission_end_ms
    emission_end_ms="$(
        awk -F'\t' '
            NR > 1 {
                value = $5
            }

            END {
                print value
            }
        ' "$stage_file"
    )"

    local pipeline_end_ms
    pipeline_end_ms="$(<"$RUN_DIR/pipeline-drained.ms")"

    local total_events
    total_events="$(get_expected_event_count)"

    local finish_time
    finish_time="$(
        awk \
            -v start="$experiment_start_ms" \
            -v end="$pipeline_end_ms" \
            'BEGIN {
                printf "%.6f", (end - start) / 1000.0
            }'
    )"

    local throughput
    throughput="$(
        awk \
            -v events="$total_events" \
            -v time="$finish_time" \
            'BEGIN {
                printf "%.6f", events / time
            }'
    )"

    local drain_time
    drain_time="$(
        awk \
            -v producer="$emission_end_ms" \
            -v end="$pipeline_end_ms" \
            'BEGIN {
                printf "%.6f", (end - producer) / 1000.0
            }'
    )"

    cat >"$RUN_DIR/dynamic-experiment-summary.tsv" <<EOF
requests	start_ms	emission_end_ms	pipeline_end_ms	finish_time_s	drain_time_s	throughput
$total_events	$experiment_start_ms	$emission_end_ms	$pipeline_end_ms	$finish_time	$drain_time	$throughput
EOF

    log "Experimental finish time: $finish_time s"
    log "Experimental throughput: $throughput event(s)/s"
    log "Observed drain time: $drain_time s"
}

validate_workloads_file() {
    [[ -f "$WORKLOADS_FILE" ]] ||
        die "Dynamic workloads file not found: $WORKLOADS_FILE"

    awk '
        {
            line = $0
            sub(/#.*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

            if (line == "") {
                next
            }

            count = split(line, fields, /[[:space:]]+/)

            if (count != 2) {
                printf("Invalid workload at line %d: expected <requests> <rate>\n", NR) > "/dev/stderr"
                exit 1
            }

            if (fields[1] !~ /^[1-9][0-9]*$/ ||
                fields[2] !~ /^[1-9][0-9]*$/) {
                printf("Invalid workload at line %d: values must be positive integers\n", NR) > "/dev/stderr"
                exit 1
            }

            workloads++
        }

        END {
            if (workloads == 0) {
                print "No workloads found" > "/dev/stderr"
                exit 1
            }
        }
    ' "$WORKLOADS_FILE" ||
        die "Invalid workloads file: $WORKLOADS_FILE"
}

get_expected_event_count() {
    awk '
        {
            line = $0
            sub(/#.*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

            if (line == "") {
                next
            }

            split(line, fields, /[[:space:]]+/)
            total += fields[1]
        }

        END {
            printf "%.0f\n", total
        }
    ' "$WORKLOADS_FILE"
}

start_dynamic_load() {
    [[ -f "$CONF_FILE" ]] ||
        die "Configuration file not found: $CONF_FILE"

    validate_workloads_file

    is_running 'kafka\.Kafka' ||
        die "Kafka is not running"

    [[ -n "$(running_flink_job_id)" ]] ||
        die "Yahoo Flink benchmark job is not running"

    if is_running 'leiningen\.core\.main.*dynamic-workloads'; then
        log "Dynamic load generator is already running"
        return
    fi

    rm -f "$RUN_DIR/load-generator.pid"
    rm -f "$LOG_DIR/load-generator.log"

    log "Starting dynamic load from: $WORKLOADS_FILE"
    log "MAX_SPEED=$MAX_SPEED"
    log "FIXED_PAYLOAD=$FIXED_PAYLOAD"
    log "PAYLOAD_POOL=$PAYLOAD_POOL"
    log "PAYLOAD_POOL_SIZE=$PAYLOAD_POOL_SIZE"

    local -a load_args=(
        -r
        --dynamic-workloads "$WORKLOADS_FILE"
        --configPath "$CONF_FILE"
    )

    case "${MAX_SPEED,,}" in
        true|1|yes|on)
            load_args+=(--max-speed)
            ;;
        false|0|no|off)
            ;;
        *)
            die "MAX_SPEED must be true or false: $MAX_SPEED"
            ;;
    esac

    case "${FIXED_PAYLOAD,,}" in
        true|1|yes|on)
            load_args+=(--fixed-payload)
            ;;
        false|0|no|off)
            ;;
        *)
            die "FIXED_PAYLOAD must be true or false: $FIXED_PAYLOAD"
            ;;
    esac

    case "${PAYLOAD_POOL,,}" in
        true|1|yes|on)
            load_args+=(
                --payload-pool
                --payload-pool-size "$PAYLOAD_POOL_SIZE"
            )
            ;;
        false|0|no|off)
            ;;
        *)
            die "PAYLOAD_POOL must be true or false: $PAYLOAD_POOL"
            ;;
    esac

    (
        cd "$PROJECT_ROOT/data"

        nohup "$LEIN" run \
            "${load_args[@]}" \
            >"$LOG_DIR/load-generator.log" 2>&1 &

        echo $! >"$RUN_DIR/load-generator.pid"
    )

    sleep 2

    [[ -f "$RUN_DIR/load-generator.pid" ]] ||
        die "Dynamic load generator PID was not recorded"
}

wait_dynamic_load() {
    [[ -f "$RUN_DIR/load-generator.pid" ]] ||
        die "Dynamic load generator PID file not found"

    local pid
    pid="$(<"$RUN_DIR/load-generator.pid")"

    log "Waiting for dynamic load generator PID $pid"

    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
    done

    rm -f "$RUN_DIR/load-generator.pid"

    if ! grep -q "Dynamic load completed:" \
        "$LOG_DIR/load-generator.log"
    then
        tail -n 50 "$LOG_DIR/load-generator.log" >&2
        die "Dynamic load generator did not complete successfully"
    fi

    log "All dynamic workloads were emitted"
}

generate_stats() {
    [[ -d "$PROJECT_ROOT/data" ]] ||
        die "Data directory not found"

    [[ -f "$CONF_FILE" ]] ||
        die "Configuration file not found: $CONF_FILE"

    log "Generating benchmark result files"

    (
        cd "$PROJECT_ROOT/data"
        "$LEIN" run -g --configPath "$CONF_FILE"
    )
}

cleanup_yahoo_savepoints() {
    if [[ ! -d "$SAVEPOINT_DIR" ]]; then
        return
    fi

    log "Removing temporary Yahoo savepoints from $SAVEPOINT_DIR"

    find "$SAVEPOINT_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name 'savepoint-*' \
        -exec rm -rf {} +
}

stop_flink_processing_gracefully() {
    local job_id
    job_id="$(get_yahoo_job_id)"

    mkdir -p "$SAVEPOINT_DIR"

    log "Gracefully stopping Flink job $job_id with drain"

    "$FLINK_HOME/bin/flink" stop \
        --drain \
        --savepointPath "$SAVEPOINT_DIR" \
        "$job_id"

    local state=""

    while true
    do
        state="$(
            curl -fsS \
                "$FLINK_REST_URL/jobs/$job_id" |
            jq -r '.state // empty'
        )"

        log "Flink job state: $state"

        case "$state" in
            FINISHED)
                break
                ;;

            FAILED|CANCELED|SUSPENDED)
                die \
                    "Graceful Flink stop terminated with unexpected state: $state"
                ;;

            *)
                sleep 1
                ;;
        esac
    done

    rm -f "$RUN_DIR/flink-job.id"

    cleanup_yahoo_savepoints

    log "Flink job finished gracefully"
}

run_dynamic_experiment() {
    rm -f \
        "$RUN_DIR/pipeline-drained.ms" \
        "$RUN_DIR/dynamic-experiment-summary.tsv"

    start_dynamic_load
    wait_dynamic_load

    log "Producer completed; waiting for actual pipeline drain"

    wait_pipeline_drain
    write_dynamic_experiment_summary

    #
    # HERE we will capture the complete terminal metrics.
    # The job is still RUNNING, but we know it has already been drained.
    #

    generate_stats
    stop_flink_processing_gracefully

    log "Dynamic experiment completed"
}

start_load() {
    [[ -f "$CONF_FILE" ]] || die "Configuration file not found: $CONF_FILE"

    if is_running 'leiningen\.core\.main.* -r '; then
        log "Load generator is already running"
        return
    fi

    log "Starting load generator at $LOAD event(s)/s"
    (
        cd "$PROJECT_ROOT/data"
        nohup "$LEIN" run -r -t "$LOAD" \
            --configPath "$CONF_FILE" \
            >"$LOG_DIR/load-generator.log" 2>&1 &
        echo $! >"$RUN_DIR/load-generator.pid"
    )

    sleep 2
}

stop_load() {
    local load_was_running=0

    if [[ -f "$RUN_DIR/load-generator.pid" ]]; then
        local pid
        pid="$(<"$RUN_DIR/load-generator.pid")"

        if kill -0 "$pid" 2>/dev/null; then
            load_was_running=1
            log "Stopping load generator"
            kill "$pid" 2>/dev/null || true
            sleep 1
        fi

        rm -f "$RUN_DIR/load-generator.pid"
    fi

    if is_running 'leiningen\.core\.main.* -r '; then
        load_was_running=1
        stop_process_if_needed 'leiningen\.core\.main.* -r ' 'Load generator'
    else
        log "No Load generator process found"
    fi

    if (( load_was_running == 1 )) && [[ -d "$PROJECT_ROOT/data" && -f "$CONF_FILE" ]]; then
        log "Generating benchmark result files"
        (
            cd "$PROJECT_ROOT/data"
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
    cat <<EOF_HELP
Yahoo Streaming Benchmark - Flink-only runner with shared services

Usage:
  $0 OPERATION [OPERATION ...]

Directory layout:
  PROJECT_ROOT=$PROJECT_ROOT
  SERVICES_ROOT=$SERVICES_ROOT

Shared services:
  FLINK_HOME=$FLINK_HOME
  KAFKA_HOME=$KAFKA_HOME
  REDIS_HOME=$REDIS_HOME

Operations:
  SETUP                    Build Yahoo Flink modules, install Redis and Kafka
                           in SERVICES_ROOT, and validate shared Flink.
  START_ZK                 Start ZooKeeper bundled with Kafka.
  STOP_ZK                  Stop ZooKeeper.
  START_REDIS              Start Redis and initialize campaign data.
  STOP_REDIS               Stop Redis.
  START_KAFKA              Start Kafka and create the benchmark topic.
  STOP_KAFKA               Stop Kafka.
  START_FLINK              Start the shared standalone Flink cluster.
  STOP_FLINK               Stop the shared standalone Flink cluster.
  START_FLINK_PROCESSING   Submit AdvertisingTopologyNative.
  STOP_FLINK_PROCESSING    Cancel the Yahoo benchmark Flink job.
  START_LOAD               Start the Kafka load generator.
  STOP_LOAD                Stop the generator and create result files.
  FLINK_TEST               Run the complete benchmark workflow.
  WRITE_CONFIG             Generate localConf.yaml.
  START_DYNAMIC_LOAD       Start workloads from dynamic-workloads.txt.
  WAIT_DYNAMIC_LOAD        Wait until all workloads have been emitted.
  GENERATE_STATS           Generate seen.txt and updated.txt.
  RUN_DYNAMIC_EXPERIMENT   Run, wait, drain, collect results and stop the job.
  STOP_ALL                 Stop all benchmark processes and services.
  HELP                     Show this message.

Frequently used environment variables:
  PROJECT_ROOT=$PROJECT_ROOT
  SERVICES_ROOT=$SERVICES_ROOT
  BENCHMARK_JAVA_HOME=${BENCHMARK_JAVA_HOME:-<current JAVA_HOME>}
  LOAD=$LOAD
  TEST_TIME=$TEST_TIME
  PARTITIONS=$PARTITIONS
  PROCESS_HOSTS=$PROCESS_HOSTS
  PROCESS_CORES=$PROCESS_CORES
  TOPIC=$TOPIC
  FLINK_VERSION=$FLINK_VERSION
  FLINK_DIR_NAME=$FLINK_DIR_NAME
  FLINK_HOME=$FLINK_HOME
  KAFKA_HOME=$KAFKA_HOME
  REDIS_HOME=$REDIS_HOME
  WORKLOADS_FILE=$WORKLOADS_FILE
  DRAIN_SECONDS=$DRAIN_SECONDS
  MAX_SPEED=$MAX_SPEED
  PARALLELISM_SOURCE=$PARALLELISM_SOURCE
  PARALLELISM_DESERIALIZE=$PARALLELISM_DESERIALIZE
  PARALLELISM_FILTER=$PARALLELISM_FILTER
  PARALLELISM_PROJECT=$PARALLELISM_PROJECT
  PARALLELISM_REDIS_JOIN=$PARALLELISM_REDIS_JOIN
  PARALLELISM_CAMPAIGN_PROCESSOR=$PARALLELISM_CAMPAIGN_PROCESSOR

Important:
  - SETUP does not download Flink. It reuses FLINK_HOME.
  - The default shared Flink directory is:
        SERVICES_ROOT/flink-2.2.0
  - Redis, Kafka, and download-cache are stored in SERVICES_ROOT.
  - Yahoo code, logs, run files, configuration, and results remain in PROJECT_ROOT.
  - For effective source parallelism P, use:
        PARTITIONS >= PROCESS_HOSTS * PROCESS_CORES
EOF_HELP
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
        WRITE_CONFIG)           write_local_config ;;
        START_DYNAMIC_LOAD)     start_dynamic_load ;;
        WAIT_DYNAMIC_LOAD)      wait_dynamic_load ;;
        GENERATE_STATS)         generate_stats ;;
        RUN_DYNAMIC_EXPERIMENT) run_dynamic_experiment ;;
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