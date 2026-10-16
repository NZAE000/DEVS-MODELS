#!/usr/bin/env bash
# -----------------------------------------------------
# generate_operator_sim_params.sh  (picoseconds version)
#
# Read:
#   subtasks/subtask_topology.txt
#   subtasks/subtask_metrics_intervals.json
#
# Generate:
#   operator.txt        -> service-time distribution and ship strategy
#   topology.txt        -> connections ordered source -> sink
#   degradation.txt     -> default degradation factors
#   extraoccupation.txt -> default extra-occupation factors
#
# Service-time parameters are calculated only from intervals marked as:
#   phase == STEADY
#   stable == true
#   baseline_eligible == true
#
# For all operators, including sources, the full mean service time is estimated
# from Flink's accumulated busy time and the number of observed invocations:
#
#   busy_mean_ns = sum(delta_busy_ms) * 1e6 / sum(delta_observed)
#
# The instrumented invocation moments estimate the distribution shape and
# relative dispersion:
#
#   sampled_mean_ns = sum(delta_time_ns) / sum(delta_samples)
#
#   sampled_variance_ns =
#       max(0, sum(delta_squared_time_ns) / sum(delta_samples)
#              - sampled_mean_ns^2)
#
#   sampled_stddev_ns = sqrt(sampled_variance_ns)
#   sampled_cv        = sampled_stddev_ns / sampled_mean_ns
#
# The full standard deviation is scaled to the busy-time mean:
#
#   full_stddev_ns = sampled_cv * busy_mean_ns
#
# Instrumented percentiles are scaled by the same mean ratio. This preserves
# the observed relative shape while matching the complete busy-time mean.
# Source rate-wait metrics are retained only as diagnostics and are not used
# to define the source service-time mean.
# extraoccupation.txt remains 1.0 for the P=1 base model.
#
# Nanoseconds are converted to picoseconds before writing operator.txt.
# -----------------------------------------------------

set -Eeuo pipefail

## Get absolute path and locate.
DIR_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$DIR_BASE" || exit 1

METRICS_DIR="$DIR_BASE/../../subtasks"
OPERLIST_DIR="$METRICS_DIR/subtask_topology.txt"
INTERVALS_FILE="$METRICS_DIR/subtask_metrics_intervals.json"
OUTPUT_PROP_FILE="$DIR_BASE/../../../input_data/operator.txt"
OUTPUT_TOPO_FILE="$DIR_BASE/../../../input_data/topology.txt"
OUTPUT_DEG_FILE="$DIR_BASE/../../../input_data/degradation.txt"
OUTPUT_OCCUP_FILE="$DIR_BASE/../../../input_data/extraoccupation.txt"

mkdir -p "$(dirname "$OUTPUT_PROP_FILE")"

if [[ ! -f "$OPERLIST_DIR" ]]; then
    echo "[ERROR] Topology file not found: $OPERLIST_DIR" >&2
    exit 1
fi

if [[ ! -f "$INTERVALS_FILE" ]]; then
    echo "[ERROR] Metrics interval file not found: $INTERVALS_FILE" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 is required to process $INTERVALS_FILE" >&2
    exit 1
fi

# Clean outputs.
> "$OUTPUT_PROP_FILE"
> "$OUTPUT_TOPO_FILE"
> "$OUTPUT_DEG_FILE"
> "$OUTPUT_OCCUP_FILE"

# Write default degradation factors.
printf "%f %f %f %f %f\n" "1.0" "1.0" "1.0" "1.0" "1.0" >> "$OUTPUT_DEG_FILE"

echo ""
echo "[INFO] Generating operator parameters..."

#######################################################################
# 1. GENERATE operator.txt
#######################################################################
python3 - \
    "$INTERVALS_FILE" \
    "$OPERLIST_DIR" \
    "$OUTPUT_PROP_FILE" \
    "$OUTPUT_OCCUP_FILE" <<'PYTHON'
from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable, Optional

INTERVALS_FILE = Path(sys.argv[1])
TOPOLOGY_FILE = Path(sys.argv[2])
OUTPUT_PROP_FILE = Path(sys.argv[3])
OUTPUT_OCCUP_FILE = Path(sys.argv[4])
NS_TO_PS = 1_000.0

# Distribution-selection thresholds.
#
# fix:
#   Nearly deterministic service time.
#
# norm:
#   Low relative dispersion and a light upper tail. Restricting CV keeps
#   the probability of generating negative service times negligible.
#
# expo:
#   CV close to 1 and an upper tail compatible with an exponential shape.
#
# gamm:
#   Positive, right-skewed service time with moderate dispersion.
#
# lnorm:
#   High dispersion or a heavy upper tail.
FIX_MAX_CV = 0.05
NORM_MAX_CV = 0.35
NORM_MAX_TAIL_SIGMAS = 1.50
EXPO_MIN_CV = 0.85
EXPO_MAX_CV = 1.15
EXPO_MAX_TAIL_SIGMAS = 2.50
GAMMA_MAX_CV = 1.00
GAMMA_MAX_TAIL_SIGMAS = 3.50


def abort(message: str) -> None:
    print(f"[ERROR] {message}", file=sys.stderr)
    raise SystemExit(1)


def as_number(value: Any) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def fmt(value: float) -> str:
    """Write stable decimal values without unnecessary trailing zeroes."""
    text = f"{value:.12f}".rstrip("0").rstrip(".")
    return "0" if text in {"", "-0"} else text


def weighted_median(values: Iterable[tuple[float, float]]) -> Optional[float]:
    samples = sorted(
        (float(value), max(0.0, float(weight)))
        for value, weight in values
        if math.isfinite(float(value))
        and math.isfinite(float(weight))
        and float(weight) > 0
    )
    if not samples:
        return None

    total_weight = sum(weight for _, weight in samples)
    midpoint = total_weight / 2.0
    accumulated = 0.0

    for value, weight in samples:
        accumulated += weight
        if accumulated >= midpoint:
            return value

    return samples[-1][0]


def load_topology() -> list[dict[str, Any]]:
    topology: list[dict[str, Any]] = []

    with TOPOLOGY_FILE.open("r", encoding="utf-8") as file:
        for line_number, raw_line in enumerate(file, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            fields = [field.strip() for field in line.split(";")]
            if len(fields) != 5:
                abort(
                    f"invalid topology line {line_number}: "
                    "expected id;name;parallelism;nexts;ship_strategy"
                )

            vertex_id, name, parallelism, nexts, ship_strategy = fields

            try:
                parallelism_value = int(parallelism)
            except ValueError:
                abort(f"invalid parallelism for operator {name!r}: {parallelism!r}")

            topology.append(
                {
                    "vertex_id": vertex_id,
                    "name": name,
                    "parallelism": parallelism_value,
                    "nexts": nexts,
                    "ship_strategy": ship_strategy,
                }
            )

    if not topology:
        abort(f"empty topology file: {TOPOLOGY_FILE}")

    return topology


def load_intervals() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    try:
        with INTERVALS_FILE.open("r", encoding="utf-8") as file:
            payload = json.load(file)
    except json.JSONDecodeError as error:
        abort(f"invalid JSON in {INTERVALS_FILE}: {error}")

    if not isinstance(payload, dict):
        abort("interval JSON root must be an object")

    metadata = payload.get("metadata", {})
    intervals = payload.get("intervals")

    if not isinstance(metadata, dict):
        metadata = {}
    if not isinstance(intervals, list):
        abort("interval JSON must contain an 'intervals' array")

    return metadata, [item for item in intervals if isinstance(item, dict)]


def eligible_intervals(intervals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        interval
        for interval in intervals
        if interval.get("phase") == "STEADY"
        and interval.get("stable") is True
        and interval.get("baseline_eligible") is True
    ]


def choose_distribution(
    mean_ps: float,
    stddev_ps: float,
    p95_ps: Optional[float],
    p99_ps: Optional[float],
) -> tuple[str, list[float], float, Optional[float]]:
    if mean_ps <= 0:
        return "fix", [1.0], 0.0, None

    cv = stddev_ps / mean_ps if stddev_ps > 0 else 0.0
    tail_sigmas = None

    if (
        stddev_ps > 0
        and p95_ps is not None
        and p99_ps is not None
        and p99_ps >= p95_ps
    ):
        tail_sigmas = (p99_ps - p95_ps) / stddev_ps

    if stddev_ps <= 0 or cv <= FIX_MAX_CV:
        return "fix", [mean_ps], cv, tail_sigmas

    if cv <= NORM_MAX_CV and (
        tail_sigmas is None or tail_sigmas <= NORM_MAX_TAIL_SIGMAS
    ):
        return "norm", [mean_ps, stddev_ps], cv, tail_sigmas

    if EXPO_MIN_CV <= cv <= EXPO_MAX_CV and (
        tail_sigmas is None or tail_sigmas <= EXPO_MAX_TAIL_SIGMAS
    ):
        return "expo", [1.0 / mean_ps], cv, tail_sigmas

    if cv <= GAMMA_MAX_CV and (
        tail_sigmas is None or tail_sigmas <= GAMMA_MAX_TAIL_SIGMAS
    ):
        variance_ps2 = stddev_ps * stddev_ps
        shape = mean_ps * mean_ps / variance_ps2
        scale_ps = variance_ps2 / mean_ps
        return "gamm", [shape, scale_ps], cv, tail_sigmas

    variance_ps2 = stddev_ps * stddev_ps
    sigma_ln = math.sqrt(math.log1p(variance_ps2 / (mean_ps * mean_ps)))
    mu_ln = math.log(mean_ps) - 0.5 * sigma_ln * sigma_ln
    return "lnorm", [mu_ln, sigma_ln], cv, tail_sigmas


def aggregate_operator(
    operator: dict[str, Any],
    intervals: list[dict[str, Any]],
) -> dict[str, Any]:
    vertex_id = operator["vertex_id"]
    total_observed = 0.0
    total_samples = 0.0
    total_time_ns = 0.0
    total_squared_time_ns = 0.0
    total_busy_ms = 0.0
    observed_available = False
    busy_available = False
    total_records_in = 0.0
    total_records_out = 0.0
    records_in_available = False
    records_out_available = False
    p95_values: list[tuple[float, float]] = []
    p99_values: list[tuple[float, float]] = []
    valid_service_entries = 0

    for interval in intervals:
        for subtask in interval.get("subtasks", []):
            if not isinstance(subtask, dict) or subtask.get("vertex_id") != vertex_id:
                continue

            records_in = as_number(subtask.get("records_in_delta"))
            records_out = as_number(subtask.get("records_out_delta"))
            busy_ms = as_number(subtask.get("busy_ms_delta"))
            observed = as_number(subtask.get("delta_observed"))

            if records_in is not None and records_in >= 0:
                total_records_in += records_in
                records_in_available = True
            if records_out is not None and records_out >= 0:
                total_records_out += records_out
                records_out_available = True
            if busy_ms is not None and busy_ms >= 0:
                total_busy_ms += busy_ms
                busy_available = True
            if observed is not None and observed >= 0:
                total_observed += observed
                observed_available = True

            if subtask.get("service_metrics_valid") is not True:
                continue
            if subtask.get("operator_stable") is not True:
                continue

            samples = as_number(subtask.get("delta_samples"))
            total_ns = as_number(subtask.get("delta_time_ns"))
            squared_ns = as_number(subtask.get("delta_squared_time_ns"))
            if samples is None or samples <= 0 or total_ns is None or total_ns < 0 or squared_ns is None or squared_ns < 0:
                continue

            total_samples += samples
            total_time_ns += total_ns
            total_squared_time_ns += squared_ns
            valid_service_entries += 1

            window = subtask.get("window_statistics", {})
            if isinstance(window, dict):
                p95 = as_number(window.get("p95_ns"))
                p99 = as_number(window.get("p99_ns"))
                if p95 is not None and p95 >= 0:
                    p95_values.append((p95, samples))
                if p99 is not None and p99 >= 0:
                    p99_values.append((p99, samples))

    destination = str(operator["nexts"]).strip().lower()
    terminal_operator = destination in {"", "0", "none", "null"}
    selectivity = 1.0
    if records_in_available and total_records_in > 0:
        if terminal_operator:
            # Flink sinks commonly report numRecordsOut = 0 because no record
            # is emitted to another vertex. Preserve neutral selectivity.
            selectivity = 1.0
        elif records_out_available:
            selectivity = total_records_out / total_records_in

    sampled_mean_ns = None
    sampled_stddev_ns = None
    sampled_cv = None
    if total_samples > 0:
        sampled_mean_ns = total_time_ns / total_samples
        sampled_variance_ns2 = max(0.0, total_squared_time_ns / total_samples - sampled_mean_ns * sampled_mean_ns)
        sampled_stddev_ns = math.sqrt(sampled_variance_ns2)
        if sampled_mean_ns > 0:
            sampled_cv = sampled_stddev_ns / sampled_mean_ns

    # The service count must match the number of times the simulator applies
    # the operator service distribution. delta_observed is the closest measure
    # of processElement invocations.
    service_count = None
    service_count_source = None
    if observed_available and total_observed > 0:
        service_count = total_observed
        service_count_source = "delta_observed"
    elif records_in_available and total_records_in > 0:
        service_count = total_records_in
        service_count_source = "records_in"
    elif records_out_available and total_records_out > 0:
        service_count = total_records_out
        service_count_source = "records_out"

    busy_mean_ns = None
    if busy_available and total_busy_ms > 0 and service_count is not None and service_count > 0:
        busy_mean_ns = total_busy_ms * 1_000_000.0 / service_count
        print("total_busy_ms:", total_busy_ms, "busy_mean_ns:", busy_mean_ns, "service_count:", service_count, "total_records_in:", total_records_in)

    # Preserve the relative variability measured by the invocation timer, but
    # scale it to the complete mean demand represented by Flink busy time.
    busy_stddev_ns = None
    scaled_p95_ns = None
    scaled_p99_ns = None
    raw_p95_ns = weighted_median(p95_values)
    raw_p99_ns = weighted_median(p99_values)
    if busy_mean_ns is not None and sampled_cv is not None:
        busy_stddev_ns = sampled_cv * busy_mean_ns
        if sampled_mean_ns is not None and sampled_mean_ns > 0:
            scale_factor = busy_mean_ns / sampled_mean_ns
            if raw_p95_ns is not None:
                scaled_p95_ns = raw_p95_ns * scale_factor
            if raw_p99_ns is not None:
                scaled_p99_ns = raw_p99_ns * scale_factor

    return {
        "total_observed": total_observed if observed_available else None,
        "total_samples": total_samples,
        "total_busy_ms": total_busy_ms if busy_available else None,
        "valid_service_entries": valid_service_entries,
        "records_in": total_records_in if records_in_available else None,
        "records_out": total_records_out if records_out_available else None,
        "selectivity": selectivity,
        "service_count": service_count,
        "service_count_source": service_count_source,
        "sampled_mean_ns": sampled_mean_ns,
        "sampled_stddev_ns": sampled_stddev_ns,
        "sampled_cv": sampled_cv,
        "busy_mean_ns": busy_mean_ns,
        "busy_stddev_ns": busy_stddev_ns,
        "p95_ns": scaled_p95_ns,
        "p99_ns": scaled_p99_ns,
    }


def aggregate_source(
    operator: dict[str, Any],
    intervals: list[dict[str, Any]],
) -> dict[str, Any]:
    vertex_id = operator["vertex_id"]
    total_records_in = 0.0
    total_records_out = 0.0
    records_in_available = False
    records_out_available = False
    total_observed = 0.0
    total_samples = 0.0
    total_time_ns = 0.0
    total_squared_time_ns = 0.0
    total_busy_ms = 0.0
    busy_available = False
    estimated_invocation_time_ns = 0.0
    total_rate_wait_time_ns = 0.0
    rate_wait_available = False
    p95_values: list[tuple[float, float]] = []
    p99_values: list[tuple[float, float]] = []
    valid_service_entries = 0

    for interval in intervals:
        for subtask in interval.get("subtasks", []):
            if not isinstance(subtask, dict) or subtask.get("vertex_id") != vertex_id:
                continue

            records_in = as_number(subtask.get("records_in_delta"))
            records_out = as_number(subtask.get("records_out_delta"))
            busy_ms = as_number(subtask.get("busy_ms_delta"))

            if records_in is not None and records_in >= 0:
                total_records_in += records_in
                records_in_available = True
            if records_out is not None and records_out >= 0:
                total_records_out += records_out
                records_out_available = True
            if busy_ms is not None and busy_ms >= 0:
                total_busy_ms += busy_ms
                busy_available = True

            # Source stability is already represented by the source-rate rules
            # used to mark the parent interval as baseline eligible. Requiring
            # operator_stable here would discard valid source samples.
            if subtask.get("service_metrics_valid") is not True:
                continue
            if subtask.get("sampling_consistent") is False:
                continue

            observed = as_number(subtask.get("delta_observed"))
            samples = as_number(subtask.get("delta_samples"))
            total_ns = as_number(subtask.get("delta_time_ns"))
            squared_ns = as_number(subtask.get("delta_squared_time_ns"))
            if observed is None or observed <= 0 or samples is None or samples <= 0 or total_ns is None or total_ns < 0 or squared_ns is None or squared_ns < 0:
                continue

            total_observed += observed
            total_samples += samples
            total_time_ns += total_ns
            total_squared_time_ns += squared_ns
            estimated_invocation_time_ns += total_ns * observed / samples
            valid_service_entries += 1

            source_metrics = subtask.get("source_metrics", {})
            if isinstance(source_metrics, dict):
                rate_wait = source_metrics.get("rate_wait", {})
                if isinstance(rate_wait, dict) and rate_wait.get("counters_valid") is True:
                    rate_wait_ns = as_number(rate_wait.get("delta_time_ns"))
                    if rate_wait_ns is not None and rate_wait_ns >= 0:
                        total_rate_wait_time_ns += rate_wait_ns
                        rate_wait_available = True

            window = subtask.get("window_statistics", {})
            if isinstance(window, dict):
                p95 = as_number(window.get("p95_ns"))
                p99 = as_number(window.get("p99_ns"))
                if p95 is not None and p95 >= 0:
                    p95_values.append((p95, samples))
                if p99 is not None and p99 >= 0:
                    p99_values.append((p99, samples))

    destination = str(operator["nexts"]).strip().lower()
    terminal_operator = destination in {"", "0", "none", "null"}
    selectivity = 1.0
    if records_in_available and total_records_in > 0:
        if terminal_operator:
            selectivity = 1.0
        elif records_out_available:
            selectivity = total_records_out / total_records_in

    sampled_mean_ns = None
    sampled_stddev_ns = None
    sampled_cv = None
    if total_samples > 0:
        sampled_mean_ns = total_time_ns / total_samples
        sampled_variance_ns2 = max(0.0, total_squared_time_ns / total_samples - sampled_mean_ns * sampled_mean_ns)
        sampled_stddev_ns = math.sqrt(sampled_variance_ns2)
        if sampled_mean_ns > 0:
            sampled_cv = sampled_stddev_ns / sampled_mean_ns

    # Use the same hybrid estimator as regular operators: the absolute mean
    # comes from exact accumulated busy time, while the instrumented samples
    # preserve the relative variability and distribution shape.
    source_mean_ns = None
    if busy_available and total_busy_ms > 0 and total_observed > 0:
        source_mean_ns = total_busy_ms * 1_000_000.0 / total_observed

    source_stddev_ns = None
    scaled_p95_ns = None
    scaled_p99_ns = None
    raw_p95_ns = weighted_median(p95_values)
    raw_p99_ns = weighted_median(p99_values)
    if source_mean_ns is not None and sampled_cv is not None:
        source_stddev_ns = sampled_cv * source_mean_ns
        if sampled_mean_ns is not None and sampled_mean_ns > 0:
            scale_factor = source_mean_ns / sampled_mean_ns
            if raw_p95_ns is not None:
                scaled_p95_ns = raw_p95_ns * scale_factor
            if raw_p99_ns is not None:
                scaled_p99_ns = raw_p99_ns * scale_factor

    return {
        "total_observed": total_observed if total_observed > 0 else None,
        "total_samples": total_samples,
        "total_busy_ms": total_busy_ms if busy_available else None,
        "valid_service_entries": valid_service_entries,
        "records_in": total_records_in if records_in_available else None,
        "records_out": total_records_out if records_out_available else None,
        "selectivity": selectivity,
        "sampled_mean_ns": sampled_mean_ns,
        "sampled_stddev_ns": sampled_stddev_ns,
        "sampled_cv": sampled_cv,
        "estimated_invocation_time_ns": estimated_invocation_time_ns if estimated_invocation_time_ns > 0 else None,
        "source_rate_wait_time_ns": total_rate_wait_time_ns if rate_wait_available else 0.0,
        "source_mean_ns": source_mean_ns,
        "source_stddev_ns": source_stddev_ns,
        "p95_ns": scaled_p95_ns,
        "p99_ns": scaled_p99_ns,
    }

topology = load_topology()
destination_ids = {
    destination.strip()
    for operator in topology
    for destination in str(operator["nexts"]).split("-")
    if destination.strip().lower() not in {"", "0", "none", "null"}
}
source_vertex_ids = {
    operator["vertex_id"]
    for operator in topology
    if operator["vertex_id"] not in destination_ids
}
if not source_vertex_ids:
    source_vertex_ids = {
        operator["vertex_id"]
        for operator in topology
        if "source" in operator["name"].lower()
    }

metadata, all_intervals = load_intervals()

baseline_mode = str(metadata.get("baseline_mode", "capacity")).strip().lower()
if baseline_mode not in {"capacity", "scalability"}:
    abort(f"unsupported baseline mode in interval metadata: {baseline_mode!r}")

baseline_intervals = eligible_intervals(all_intervals)

if not baseline_intervals:
    steady_regimes = metadata.get("steady_regime_counts")
    configured_rate = metadata.get("configured_arrival_rate_records_per_second")
    details: list[str] = []

    if configured_rate is not None:
        details.append(f"configured arrival rate={configured_rate}")
    if isinstance(steady_regimes, dict):
        details.append(f"STEADY regimes={steady_regimes}")

    suffix = f" ({', '.join(details)})" if details else ""
    abort(
        "no baseline-eligible intervals were found. Operator service-time "
        "parameters must be generated from intervals accepted by "
        "generate_metrics_intervals_from_snapshots.py for "
        f"baseline_mode={baseline_mode!r}{suffix}."
    )

print(f"[INFO] Baseline mode: {baseline_mode}")
print(
    "[INFO] Using "
    f"{len(baseline_intervals)} baseline-eligible interval(s) "
    f"out of {len(all_intervals)}."
)

configured_requests = metadata.get("configured_request_count")
configured_rate = metadata.get("configured_arrival_rate_records_per_second")
if configured_requests is not None:
    print(f"[INFO] Configured requests: {configured_requests}")
if configured_rate is not None:
    print(f"[INFO] Configured arrival rate: {configured_rate} records/s")

with (
    OUTPUT_PROP_FILE.open("a", encoding="utf-8") as property_file,
    OUTPUT_OCCUP_FILE.open("a", encoding="utf-8") as occupation_file,
):
    for operator in topology:
        name = operator["name"]
        parallelism = operator["parallelism"]
        ship_strategy = operator["ship_strategy"]
        is_source = operator["vertex_id"] in source_vertex_ids

        print(f"[INFO] Processing {name} ...")
        occupation_file.write(f"{name:<20} {fmt(1.0)}\n")

        if is_source:
            aggregate = aggregate_source(operator, baseline_intervals)
            selectivity = float(aggregate["selectivity"])
            source_mean_ns = aggregate["source_mean_ns"]
            source_stddev_ns = aggregate["source_stddev_ns"]
            sampled_cv = aggregate["sampled_cv"]

            if source_mean_ns is None or source_mean_ns <= 0:
                distribution = "fix"
                arguments = [1.0]
                print(
                    "  -> no valid source busy-time mean could be estimated; "
                    "using technical fallback fix 1 ps"
                )
            elif source_stddev_ns is None or sampled_cv is None:
                mean_ps = float(source_mean_ns) * NS_TO_PS
                distribution = "fix"
                arguments = [mean_ps]
                print(
                    f"  -> source busy-time mean available without a valid "
                    f"instrumented CV: observed={aggregate['total_observed']:.0f}, "
                    f"busy={aggregate['total_busy_ms']:.6f} ms, "
                    f"mean={mean_ps:.6f} ps, distribution=fix"
                )
            else:
                mean_ps = float(source_mean_ns) * NS_TO_PS
                stddev_ps = float(source_stddev_ns) * NS_TO_PS
                p95_ns = aggregate["p95_ns"]
                p99_ns = aggregate["p99_ns"]
                p95_ps = float(p95_ns) * NS_TO_PS if p95_ns is not None else None
                p99_ps = float(p99_ns) * NS_TO_PS if p99_ns is not None else None
                distribution, arguments, cv, tail_sigmas = choose_distribution(mean_ps, stddev_ps, p95_ps, p99_ps)
                tail_text = "n/a" if tail_sigmas is None else f"{tail_sigmas:.4f}"
                sampled_mean_ps = float(aggregate["sampled_mean_ns"]) * NS_TO_PS
                estimated_ns = aggregate["estimated_invocation_time_ns"]
                rate_wait_ns = aggregate["source_rate_wait_time_ns"]
                print(
                    f"  -> source entries={aggregate['valid_service_entries']}, "
                    f"observed={aggregate['total_observed']:.0f}, "
                    f"samples={aggregate['total_samples']:.0f}, "
                    f"busy={aggregate['total_busy_ms']:.6f} ms, "
                    f"estimated_invocation={estimated_ns:.3f} ns, "
                    f"rate_wait={rate_wait_ns:.3f} ns, "
                    f"sampled_mean={sampled_mean_ps:.6f} ps, "
                    f"full_mean={mean_ps:.6f} ps, "
                    f"full_stddev={stddev_ps:.6f} ps, "
                    f"CV={cv:.6f}, tail_sigma={tail_text}, "
                    f"distribution={distribution}"
                )
        else:
            print("name:", name)
            aggregate = aggregate_operator(operator, baseline_intervals)
            selectivity = float(aggregate["selectivity"])
            busy_mean_ns = aggregate["busy_mean_ns"]
            busy_stddev_ns = aggregate["busy_stddev_ns"]
            sampled_cv = aggregate["sampled_cv"]

            if busy_mean_ns is None or busy_mean_ns <= 0:
                distribution = "fix"
                arguments = [1.0]
                print(
                    "  -> no valid busy-time mean could be estimated; "
                    "using technical fallback fix 1 ps"
                )
            elif busy_stddev_ns is None or sampled_cv is None:
                mean_ps = float(busy_mean_ns) * NS_TO_PS
                distribution = "fix"
                arguments = [mean_ps]
                print(
                    f"  -> full busy-time mean available without a valid "
                    f"instrumented CV: mean={mean_ps:.6f} ps, distribution=fix"
                )
            else:
                mean_ps = float(busy_mean_ns) * NS_TO_PS
                stddev_ps = float(busy_stddev_ns) * NS_TO_PS
                p95_ns = aggregate["p95_ns"]
                p99_ns = aggregate["p99_ns"]
                p95_ps = float(p95_ns) * NS_TO_PS if p95_ns is not None else None
                p99_ps = float(p99_ns) * NS_TO_PS if p99_ns is not None else None
                distribution, arguments, cv, tail_sigmas = choose_distribution(mean_ps, stddev_ps, p95_ps, p99_ps)
                tail_text = "n/a" if tail_sigmas is None else f"{tail_sigmas:.4f}"
                sampled_mean_ps = float(aggregate["sampled_mean_ns"]) * NS_TO_PS if aggregate["sampled_mean_ns"] is not None else None
                sampled_mean_text = "n/a" if sampled_mean_ps is None else f"{sampled_mean_ps:.6f}"
                print(
                    f"  -> observed={aggregate['total_observed']:.0f}, "
                    f"samples={aggregate['total_samples']:.0f}, "
                    f"busy={aggregate['total_busy_ms']:.6f} ms, "
                    f"sampled_mean={sampled_mean_text} ps, "
                    f"full_mean={mean_ps:.6f} ps, "
                    f"full_stddev={stddev_ps:.6f} ps, "
                    f"CV={cv:.6f}, tail_sigma={tail_text}, "
                    f"distribution={distribution}"
                )

        args_text = " ".join(fmt(float(value)) for value in arguments)
        property_file.write(
            f"{name:<20} {parallelism} {distribution:<8} {args_text} "
            f"{ship_strategy} {fmt(selectivity)}\n"
        )

PYTHON

echo "[SUCCESS] Operator parameters generated in $OUTPUT_PROP_FILE"
echo ""

#######################################################################
# 2. GENERATE topology.txt using only subtask_topology.txt
#######################################################################
echo "[INFO] Generating topology from subtask_topology.txt..."

# subtask_topology.txt is already ordered from source to sink.
# Format: ID ; NAME ; PAR ; NEXT1-NEXT2 ; SHIP
while IFS=';' read -r ID NAME PAR NEXTS SHIP; do
    # Ignore empty lines and comments.
    [[ -z "$ID" || "$ID" == \#* ]] && continue

    # NEXTS may be "0" or "A-B-C".
    if [[ "$NEXTS" == "0" ]]; then
        continue
    fi

    # Split successor IDs.
    IFS='-' read -ra TARGETS <<< "$NEXTS"

    for T in "${TARGETS[@]}"; do
        # Convert the destination ID to its operator name.
        TO_NAME=$(grep "^$T;" "$OPERLIST_DIR" | cut -d';' -f2 || true)

        if [[ -n "$TO_NAME" ]]; then
            echo "$NAME $TO_NAME" >> "$OUTPUT_TOPO_FILE"
        fi
    done
done < "$OPERLIST_DIR"

echo "[SUCCESS] Topology generated in $OUTPUT_TOPO_FILE"
echo "---------------------------------------------"
echo ""