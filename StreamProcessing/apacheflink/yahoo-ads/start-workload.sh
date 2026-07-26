#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
load=$1

LOAD=$load \
"$SCRIPT_DIR/stream-bench.sh" START_LOAD