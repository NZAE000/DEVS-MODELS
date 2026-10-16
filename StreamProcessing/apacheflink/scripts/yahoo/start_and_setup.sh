#!/usr/bin/env bash

set -Eeuo pipefail

DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
APACHEFLINK_DIR="$DIR_BASE/../.."
YAHOO_DIR="$APACHEFLINK_DIR/yahoo-ads"

readonly KAFKA_PARTITIONS=32

bash "$YAHOO_DIR/start-services.sh" "$KAFKA_PARTITIONS"