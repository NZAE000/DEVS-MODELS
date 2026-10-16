#!/usr/bin/env bash

set -Eeuo pipefail

DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
APACHEFLINK_DIR="$DIR_BASE/../.."
YAHOO_DIR="$APACHEFLINK_DIR/yahoo-ads"

DRAIN_SECONDS="${1:-30}"

bash "$YAHOO_DIR/start-dynamic-workload.sh" "$DRAIN_SECONDS"