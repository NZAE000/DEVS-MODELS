#!/usr/bin/env python3
"""Generate metric intervals and WARMUP/STEADY/DRAIN labels.

Implemented Processing: For each pair of consecutive snapshots, it calculates:
    - actual interval duration using timestamp_ms;
    - input and output register deltas;
    - input and output throughput;
    - busy, idle, and backpressure deltas;
    - busy, idle, and backpressure ratios;
    - instrumented metric deltas;
    - mean and standard deviation per interval;
    - estimated uptime;
    - approximate internal occupancy;
    - timer deltas;
    - counter reset detection.

For each interval, cumulative instrumentation metrics are converted
into deltas between two consecutive snapshots:

   delta_samples         = samples(t_i) - samples(t_{i-1})
   delta_time_ns         = total_time_ns(t_i) - total_time_ns(t_{i-1})
   delta_squared_time_ns = squared_total_time_ns(t_i) - squared_total_time_ns(t_{i-1})

The mean invocation time for the interval is:

   mean_invocation_ns = delta_time_ns / delta_samples

The population variance for the interval is:

   variance_invocation_ns = (delta_squared_time_ns / delta_samples) - mean_invocation_ns**2

The standard deviation is:

   stddev_invocation_ns = sqrt(max(0.0, variance_invocation_ns))

max(0.0, ...) avoids small negative values caused by floating-point precision errors.
    
Expected location:
    scripts/common/generate_metrics_intervals_from_snapshots.py

Parameters:
    1. request_count: total number of workload requests/events.
    2. arrival_rate: configured arrival rate in records per second.

Inputs:
    subtask/subtask_metrics_snapshots.json
    subtask/subtask_topology.txt

Output:
    subtask/subtask_metrics_intervals.json
"""

from __future__ import annotations

import json
import math
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


# =============================================================================
# Paths
# =============================================================================
DIR_BASE = Path(__file__).resolve().parent
PROJECT_ROOT = DIR_BASE.parent.parent

SNAPSHOTS_FILE = (
    PROJECT_ROOT / "subtasks" / "subtask_metrics_snapshots.json"
)
OPERATORS_FILE = PROJECT_ROOT / "subtasks" / "subtask_topology.txt"
OUTPUT_FILE = PROJECT_ROOT / "subtasks" / "subtask_metrics_intervals.json"


# =============================================================================
# Initial classification thresholds
# =============================================================================
SMOOTH_WINDOW_MS = 3_000
STEADY_CONFIRMATION_MS = 3_000
MIN_STEADY_DURATION_MS = 10_000

SOURCE_RATE_RELATIVE_TOLERANCE = 0.05
SOURCE_RATE_ROBUST_CV_TOLERANCE = 0.05

OPERATOR_MEAN_ROBUST_CV_TOLERANCE = 0.10
MIN_STABLE_OPERATOR_FRACTION = 0.80
MIN_SAMPLES_PER_INTERVAL = 30

STATE_RATIO_ABSOLUTE_TOLERANCE = 0.10
MIN_STABLE_STATE_FRACTION = 0.80

BASELINE_MAX_BACKPRESSURE_RATIO = 0.01

# A STEADY interval satisfies the configured rate when its smoothed source
# throughput reaches at least this fraction of the requested arrival rate.
CONFIGURED_RATE_SATISFACTION_RATIO = 0.95

# Capacity saturation can also be identified when the source remains almost
# continuously busy while its effective throughput is below the configured rate.
SOURCE_BUSY_SATURATION_THRESHOLD = 0.95

# DRAIN must be observed as a final sequence of intervals where the source no
# longer emits, while downstream subtasks still make progress.
MIN_DRAIN_CONFIRMATION_INTERVALS = 2
MIN_DRAIN_CONFIRMATION_MS = 1_000


# =============================================================================
# Metric names
# =============================================================================
NATIVE_COUNTERS = {
    "records_in": "numRecordsIn",
    "records_out": "numRecordsOut",
    "busy_ms": "accumulateBusyTimeMs",
    "idle_ms": "accumulateIdleTimeMs",
    "backpressure_ms": "accumulateBackPressuredTimeMs",
    "fired_timers": "numFiredTimers",
}

OPERATOR_COUNTER_SUFFIXES = {
    "observed": ".operatorRecordInvocationsObserved",
    "samples": ".operatorRecordInvocationSamples",
    "time_ns": ".operatorRecordInvocationTimeNsTotal",
    "time_ns_squared": ".operatorRecordInvocationTimeNsSquaredTotal",
}

SOURCE_COUNTER_SUFFIXES = {
    "observed": ".sourceRecordInvocationsObserved",
    "samples": ".sourceRecordInvocationSamples",
    "time_ns": ".sourceRecordInvocationTimeNsTotal",
    "time_ns_squared": ".sourceRecordInvocationTimeNsSquaredTotal",
}

OPERATOR_WINDOW_METRIC_SUFFIXES = {
    "sample_every": ".operatorRecordInvocationSampleEvery",
    "window_size": ".operatorRecordInvocationWindowSize",
    "mean_ns": ".operatorRecordInvocationTimeNs_mean",
    "stddev_ns": ".operatorRecordInvocationTimeNs_stddev",
    "min_ns": ".operatorRecordInvocationTimeNs_min",
    "max_ns": ".operatorRecordInvocationTimeNs_max",
    "median_ns": ".operatorRecordInvocationTimeNs_median",
    "p75_ns": ".operatorRecordInvocationTimeNs_p75",
    "p90_ns": ".operatorRecordInvocationTimeNs_p90",
    "p95_ns": ".operatorRecordInvocationTimeNs_p95",
    "p98_ns": ".operatorRecordInvocationTimeNs_p98",
    "p99_ns": ".operatorRecordInvocationTimeNs_p99",
    "p999_ns": ".operatorRecordInvocationTimeNs_p999",
}

SOURCE_WINDOW_METRIC_SUFFIXES = {
    "sample_every": ".sourceRecordInvocationSampleEvery",
    "window_size": ".sourceRecordInvocationWindowSize",
    "mean_ns": ".sourceRecordInvocationTimeNs_mean",
    "stddev_ns": ".sourceRecordInvocationTimeNs_stddev",
    "min_ns": ".sourceRecordInvocationTimeNs_min",
    "max_ns": ".sourceRecordInvocationTimeNs_max",
    "median_ns": ".sourceRecordInvocationTimeNs_median",
    "p75_ns": ".sourceRecordInvocationTimeNs_p75",
    "p90_ns": ".sourceRecordInvocationTimeNs_p90",
    "p95_ns": ".sourceRecordInvocationTimeNs_p95",
    "p98_ns": ".sourceRecordInvocationTimeNs_p98",
    "p99_ns": ".sourceRecordInvocationTimeNs_p99",
    "p999_ns": ".sourceRecordInvocationTimeNs_p999",
}

SOURCE_COMPONENT_SUFFIXES = {
    "generation": {
        "time_ns": ".sourceGenerationTimeNsTotal",
        "time_ns_squared": ".sourceGenerationTimeNsSquaredTotal",
        "window_prefix": ".sourceGenerationTimeNs",
    },
    "emit": {
        "time_ns": ".sourceEmitTimeNsTotal",
        "time_ns_squared": ".sourceEmitTimeNsSquaredTotal",
        "window_prefix": ".sourceEmitTimeNs",
    },
    "framework": {
        "time_ns": ".sourceFrameworkTimeNsTotal",
        "time_ns_squared": ".sourceFrameworkTimeNsSquaredTotal",
        "window_prefix": ".sourceFrameworkTimeNs",
    },
}

SOURCE_RATE_WAIT_SUFFIXES = {
    "events": ".sourceRateWaitEventsObserved",
    "time_ns": ".sourceRateWaitTimeNsTotal",
    "time_ns_squared": ".sourceRateWaitTimeNsSquaredTotal",
}


# =============================================================================
# Basic helpers
# =============================================================================
def abort(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


def positive_integer_argument(value: str, name: str) -> int:
    try:
        number = int(value)
    except ValueError:
        abort(f"{name} must be a positive integer: {value}")

    if number <= 0:
        abort(f"{name} must be greater than zero: {value}")

    return number


def to_float(value: Any) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None

    return number if math.isfinite(number) else None


def to_bool(value: Any) -> Optional[bool]:
    if isinstance(value, bool):
        return value

    if value is None:
        return None

    text = str(value).strip().lower()
    if text in {"true", "1"}:
        return True
    if text in {"false", "0"}:
        return False
    return None


def rounded(value: Optional[float], digits: int = 9) -> Optional[float]:
    return None if value is None else round(value, digits)


def median(values: list[float]) -> Optional[float]:
    return float(statistics.median(values)) if values else None


def robust_cv(values: list[float]) -> Optional[float]:
    """Robust coefficient of variation: 1.4826 * MAD / median."""
    if len(values) < 2:
        return None

    center = statistics.median(values)
    if center == 0:
        return 0.0 if all(value == 0 for value in values) else None

    mad = statistics.median(abs(value - center) for value in values)
    return float(1.4826 * mad / abs(center))


def metric_dict(subtask: dict[str, Any]) -> dict[str, Any]:
    return {
        metric["id"]: metric.get("value")
        for metric in subtask.get("metrics", [])
        if isinstance(metric, dict) and isinstance(metric.get("id"), str)
    }


def exact_metric(metrics: dict[str, Any], metric_id: str) -> Optional[float]:
    return to_float(metrics.get(metric_id))


def suffix_metric(metrics: dict[str, Any], suffix: str) -> Optional[float]:
    for metric_id, value in metrics.items():
        if metric_id.endswith(suffix):
            return to_float(value)
    return None


def delta(previous: Optional[float], current: Optional[float]) -> tuple[Optional[float], bool]:
    """Return the counter delta and whether a reset was detected."""
    if previous is None or current is None:
        return None, False
    if current < previous:
        return None, True
    return current - previous, False


# =============================================================================
# Load input files
# =============================================================================
def load_topology() -> list[dict[str, Any]]:
    if not OPERATORS_FILE.is_file():
        abort(f"file not found: {OPERATORS_FILE}")

    topology: list[dict[str, Any]] = []

    with OPERATORS_FILE.open("r", encoding="utf-8") as file:
        for line_number, raw_line in enumerate(file, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            fields = [field.strip() for field in line.split(";")]
            if len(fields) != 5:
                abort(
                    f"invalid line {line_number} in {OPERATORS_FILE.name}: "
                    "expected id;name;p;id_to;exchange"
                )

            vertex_id, name, parallelism, destination, exchange = fields

            try:
                parallelism_value = int(parallelism)
            except ValueError:
                abort(f"invalid parallelism at line {line_number}: {parallelism}")

            topology.append(
                {
                    "vertex_id": vertex_id,
                    "name": name,
                    "parallelism": parallelism_value,
                    "destination_vertex_id": destination,
                    "exchange": exchange,
                    "order": len(topology),
                }
            )

    if not topology:
        abort(f"empty topology file: {OPERATORS_FILE}")

    return topology


def load_snapshots() -> list[dict[str, Any]]:
    if not SNAPSHOTS_FILE.is_file():
        abort(f"file not found: {SNAPSHOTS_FILE}")

    try:
        with SNAPSHOTS_FILE.open("r", encoding="utf-8") as file:
            payload = json.load(file)
    except json.JSONDecodeError as error:
        abort(f"invalid JSON in {SNAPSHOTS_FILE}: {error}")

    # Also support a future {"metadata": ..., "snapshots": [...]} format.
    if isinstance(payload, dict):
        payload = payload.get("snapshots")

    if not isinstance(payload, list):
        abort("snapshot JSON must be an array")

    snapshots = [item for item in payload if isinstance(item, dict)]
    snapshots.sort(
        key=lambda item: (
            int(item.get("timestamp_ms", 0)),
            int(item.get("snapshot_id", 0)),
        )
    )

    if len(snapshots) < 2:
        abort("at least two snapshots are required")

    previous_timestamp: Optional[int] = None
    for snapshot in snapshots:
        try:
            timestamp = int(snapshot["timestamp_ms"])
        except (KeyError, TypeError, ValueError):
            abort("a snapshot contains an invalid timestamp_ms")

        if previous_timestamp is not None and timestamp <= previous_timestamp:
            abort("snapshot timestamps must be strictly increasing")

        previous_timestamp = timestamp

    return snapshots


def detect_source_vertices(topology: list[dict[str, Any]]) -> list[str]:
    destinations = {
        operator["destination_vertex_id"]
        for operator in topology
        if operator["destination_vertex_id"] not in {"", "0", "none", "null"}
    }

    sources = [
        operator["vertex_id"]
        for operator in topology
        if operator["vertex_id"] not in destinations
    ]

    if sources:
        return sources

    return [
        operator["vertex_id"]
        for operator in topology
        if "source" in operator["name"].lower()
    ]


def snapshot_subtasks(snapshot: dict[str, Any]) -> dict[tuple[str, int], dict[str, Any]]:
    subtasks: dict[tuple[str, int], dict[str, Any]] = {}

    for entry in snapshot.get("operators", []):
        if not isinstance(entry, dict):
            continue

        vertex_id = entry.get("vertex_id")
        try:
            subtask_index = int(entry.get("subtask"))
        except (TypeError, ValueError):
            continue

        if isinstance(vertex_id, str):
            subtasks[(vertex_id, subtask_index)] = entry

    return subtasks


# =============================================================================
# Build deltas between snapshots
# =============================================================================
def source_component_window_statistics(
    metrics: dict[str, Any],
    metric_prefix: str,
) -> dict[str, Optional[float]]:
    statistics = {
        "mean_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_mean")),
        "stddev_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_stddev")),
        "min_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_min")),
        "max_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_max")),
        "median_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_median")),
        "p75_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_p75")),
        "p90_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_p90")),
        "p95_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_p95")),
        "p98_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_p98")),
        "p99_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_p99")),
        "p999_ns": rounded(suffix_metric(metrics, f"{metric_prefix}_p999")),
    }
    return {} if all(value is None for value in statistics.values()) else statistics


def source_component_interval(
    previous_metrics: dict[str, Any],
    current_metrics: dict[str, Any],
    samples: Optional[float],
    interval_duration_ms: int,
    suffixes: dict[str, str],
) -> tuple[dict[str, Any], list[str]]:
    total_ns, total_reset = delta(
        suffix_metric(previous_metrics, suffixes["time_ns"]),
        suffix_metric(current_metrics, suffixes["time_ns"]),
    )
    squared_ns, squared_reset = delta(
        suffix_metric(previous_metrics, suffixes["time_ns_squared"]),
        suffix_metric(current_metrics, suffixes["time_ns_squared"]),
    )

    resets: list[str] = []
    if total_reset:
        resets.append(suffixes["time_ns"].removeprefix("."))
    if squared_reset:
        resets.append(suffixes["time_ns_squared"].removeprefix("."))

    available = all(
        suffix_metric(current_metrics, suffixes[name]) is not None
        for name in ("time_ns", "time_ns_squared")
    )
    valid = bool(
        not resets
        and samples is not None
        and samples > 0
        and total_ns is not None
        and total_ns >= 0
        and squared_ns is not None
        and squared_ns >= 0
    )

    mean_ns = None
    variance_ns2 = None
    stddev_ns = None
    ratio = None

    if valid:
        mean_ns = total_ns / samples
        variance_ns2 = max(0.0, squared_ns / samples - mean_ns**2)
        stddev_ns = math.sqrt(variance_ns2)
        ratio = total_ns / (interval_duration_ms * 1_000_000)

    return {
        "available": available,
        "valid": valid,
        "delta_time_ns": rounded(total_ns),
        "delta_squared_time_ns": rounded(squared_ns),
        "mean_ns": rounded(mean_ns),
        "variance_ns2": rounded(variance_ns2),
        "stddev_ns": rounded(stddev_ns),
        "sampled_ratio": rounded(ratio),
        "window_statistics": source_component_window_statistics(
            current_metrics,
            suffixes["window_prefix"],
        ),
    }, resets


def source_rate_wait_interval(
    previous_metrics: dict[str, Any],
    current_metrics: dict[str, Any],
    interval_duration_ms: int,
) -> tuple[dict[str, Any], list[str]]:
    deltas: dict[str, Optional[float]] = {}
    resets: list[str] = []

    for name, suffix in SOURCE_RATE_WAIT_SUFFIXES.items():
        value, reset = delta(
            suffix_metric(previous_metrics, suffix),
            suffix_metric(current_metrics, suffix),
        )
        deltas[name] = value
        if reset:
            resets.append(suffix.removeprefix("."))

    events = deltas["events"]
    total_ns = deltas["time_ns"]
    squared_ns = deltas["time_ns_squared"]
    available = all(
        suffix_metric(current_metrics, suffix) is not None
        for suffix in SOURCE_RATE_WAIT_SUFFIXES.values()
    )
    counters_valid = bool(
        not resets
        and events is not None
        and events >= 0
        and total_ns is not None
        and total_ns >= 0
        and squared_ns is not None
        and squared_ns >= 0
    )

    mean_ns = None
    variance_ns2 = None
    stddev_ns = None

    if counters_valid and events is not None and events > 0:
        mean_ns = total_ns / events
        variance_ns2 = max(0.0, squared_ns / events - mean_ns**2)
        stddev_ns = math.sqrt(variance_ns2)

    ratio = (
        total_ns / (interval_duration_ms * 1_000_000)
        if counters_valid and total_ns is not None
        else None
    )

    return {
        "available": available,
        "counters_valid": counters_valid,
        "statistics_valid": bool(counters_valid and events is not None and events > 0),
        "delta_events_observed": rounded(events),
        "delta_time_ns": rounded(total_ns),
        "delta_squared_time_ns": rounded(squared_ns),
        "mean_ns": rounded(mean_ns),
        "variance_ns2": rounded(variance_ns2),
        "stddev_ns": rounded(stddev_ns),
        "ratio": rounded(ratio),
        "window_statistics": source_component_window_statistics(
            current_metrics,
            ".sourceRateWaitTimeNs",
        ),
    }, resets


def build_subtask_interval(
    previous: Optional[dict[str, Any]],
    current: Optional[dict[str, Any]],
    topology_operator: Optional[dict[str, Any]],
    vertex_id: str,
    subtask_index: int,
    interval_duration_ms: int,
) -> dict[str, Any]:
    previous_metrics = metric_dict(previous or {})
    current_metrics = metric_dict(current or {})
    reference = current or previous or {}

    native_deltas: dict[str, Optional[float]] = {}
    native_resets: list[str] = []

    for name, metric_id in NATIVE_COUNTERS.items():
        value, reset = delta(
            exact_metric(previous_metrics, metric_id),
            exact_metric(current_metrics, metric_id),
        )
        native_deltas[name] = value
        if reset:
            native_resets.append(metric_id)

    source_available = all(
        suffix_metric(current_metrics, suffix) is not None
        for suffix in SOURCE_COUNTER_SUFFIXES.values()
    )
    operator_available = all(
        suffix_metric(current_metrics, suffix) is not None
        for suffix in OPERATOR_COUNTER_SUFFIXES.values()
    )

    if source_available:
        service_family = "SOURCE"
        counter_suffixes = SOURCE_COUNTER_SUFFIXES
        window_suffixes = SOURCE_WINDOW_METRIC_SUFFIXES
    elif operator_available:
        service_family = "OPERATOR"
        counter_suffixes = OPERATOR_COUNTER_SUFFIXES
        window_suffixes = OPERATOR_WINDOW_METRIC_SUFFIXES
    else:
        service_family = None
        counter_suffixes = OPERATOR_COUNTER_SUFFIXES
        window_suffixes = OPERATOR_WINDOW_METRIC_SUFFIXES

    service_deltas: dict[str, Optional[float]] = {}
    service_resets: list[str] = []

    for name, suffix in counter_suffixes.items():
        value, reset = delta(
            suffix_metric(previous_metrics, suffix),
            suffix_metric(current_metrics, suffix),
        )
        service_deltas[name] = value
        if reset:
            service_resets.append(suffix.removeprefix("."))

    samples = service_deltas["samples"]
    observed = service_deltas["observed"]
    total_ns = service_deltas["time_ns"]
    squared_ns = service_deltas["time_ns_squared"]

    service_metrics_available = source_available or operator_available
    service_metrics_valid = bool(
        service_metrics_available
        and not service_resets
        and samples is not None
        and samples > 0
        and observed is not None
        and observed >= 0
        and total_ns is not None
        and total_ns >= 0
        and squared_ns is not None
        and squared_ns >= 0
    )

    mean_ns = None
    variance_ns2 = None
    stddev_ns = None
    productive_time_ns = None
    productive_ratio = None

    if service_metrics_valid:
        mean_ns = total_ns / samples
        variance_ns2 = max(0.0, squared_ns / samples - mean_ns**2)
        stddev_ns = math.sqrt(variance_ns2)
        productive_time_ns = total_ns * observed / samples
        productive_ratio = productive_time_ns / (interval_duration_ms * 1_000_000)

    seconds = interval_duration_ms / 1000
    throughput_in = (
        native_deltas["records_in"] / seconds
        if native_deltas["records_in"] is not None
        else None
    )
    throughput_out = (
        native_deltas["records_out"] / seconds
        if native_deltas["records_out"] is not None
        else None
    )

    busy_ratio = (
        native_deltas["busy_ms"] / interval_duration_ms
        if native_deltas["busy_ms"] is not None
        else None
    )
    idle_ratio = (
        native_deltas["idle_ms"] / interval_duration_ms
        if native_deltas["idle_ms"] is not None
        else None
    )
    backpressure_ratio = (
        native_deltas["backpressure_ms"] / interval_duration_ms
        if native_deltas["backpressure_ms"] is not None
        else None
    )

    ratios = [busy_ratio, idle_ratio, backpressure_ratio]
    state_metrics_valid = bool(
        not native_resets
        and all(value is not None for value in ratios)
        and all(0 <= float(value) <= 1.25 for value in ratios)
        and 0.50 <= sum(float(value) for value in ratios) <= 1.50
    )

    internal_occupancy_ratio = None
    if busy_ratio is not None and productive_ratio is not None:
        internal_occupancy_ratio = max(0.0, busy_ratio - productive_ratio)

    window_statistics = {
        name: rounded(suffix_metric(current_metrics, suffix))
        for name, suffix in window_suffixes.items()
    }
    if all(value is None for value in window_statistics.values()):
        window_statistics = {}

    sample_every = window_statistics.get("sample_every")
    expected_delta_samples = None
    sampling_consistent = None

    if (
        service_family == "SOURCE"
        and sample_every is not None
        and sample_every > 0
    ):
        previous_observed = suffix_metric(
            previous_metrics,
            SOURCE_COUNTER_SUFFIXES["observed"],
        )
        current_observed = suffix_metric(
            current_metrics,
            SOURCE_COUNTER_SUFFIXES["observed"],
        )

        if previous_observed is not None and current_observed is not None:
            expected_delta_samples = (
                math.floor(current_observed / sample_every)
                - math.floor(previous_observed / sample_every)
            )
            if samples is not None:
                sampling_consistent = abs(samples - expected_delta_samples) <= 1

    source_metrics: dict[str, Any] = {}
    source_resets: list[str] = []

    if service_family == "SOURCE":
        components: dict[str, Any] = {}

        for component_name, suffixes in SOURCE_COMPONENT_SUFFIXES.items():
            component, resets = source_component_interval(
                previous_metrics,
                current_metrics,
                samples,
                interval_duration_ms,
                suffixes,
            )
            components[component_name] = component
            source_resets.extend(resets)

        rate_wait, resets = source_rate_wait_interval(
            previous_metrics,
            current_metrics,
            interval_duration_ms,
        )
        source_resets.extend(resets)

        component_total = sum(
            float(component["delta_time_ns"])
            for component in components.values()
            if component.get("delta_time_ns") is not None
        )
        component_difference = (
            total_ns - component_total
            if total_ns is not None
            else None
        )

        source_metrics = {
            "measure_output": to_bool(
                next(
                    (
                        value
                        for metric_id, value in current_metrics.items()
                        if metric_id.endswith(
                            ".sourceRecordInvocationMeasureOutput"
                        )
                    ),
                    None,
                )
            ),
            "components": components,
            "rate_wait": rate_wait,
            "component_delta_time_ns_sum": rounded(component_total),
            "component_delta_time_ns_difference": rounded(component_difference),
            "component_times_consistent": (
                abs(component_difference) <= 1.0
                if component_difference is not None
                else None
            ),
        }

    operator_name = reference.get("operator")
    if not operator_name and topology_operator:
        operator_name = topology_operator["name"]

    all_resets = native_resets + service_resets + source_resets

    return {
        "operator": operator_name,
        "vertex_id": vertex_id,
        "subtask": subtask_index,
        "parallelism": topology_operator["parallelism"] if topology_operator else None,
        "counter_reset_detected": bool(all_resets),
        "reset_metrics": all_resets,
        "service_metric_family": service_family,
        "service_metrics_available": service_metrics_available,
        "service_metrics_valid": service_metrics_valid,
        "state_metrics_valid": state_metrics_valid,
        "operator_stable": False,
        "state_stable": False,
        "baseline_eligible": False,
        "sample_every": rounded(sample_every),
        "expected_delta_samples": rounded(expected_delta_samples),
        "sampling_consistent": sampling_consistent,
        "delta_observed": rounded(observed),
        "delta_samples": rounded(samples),
        "delta_time_ns": rounded(total_ns),
        "delta_squared_time_ns": rounded(squared_ns),
        "mean_invocation_ns": rounded(mean_ns),
        "variance_invocation_ns2": rounded(variance_ns2),
        "stddev_invocation_ns": rounded(stddev_ns),
        "estimated_productive_time_ns": rounded(productive_time_ns),
        "productive_ratio": rounded(productive_ratio),
        "internal_occupancy_ratio": rounded(internal_occupancy_ratio),
        "records_in_delta": rounded(native_deltas["records_in"]),
        "records_out_delta": rounded(native_deltas["records_out"]),
        "throughput_in_records_per_second": rounded(throughput_in),
        "throughput_out_records_per_second": rounded(throughput_out),
        "busy_ms_delta": rounded(native_deltas["busy_ms"]),
        "idle_ms_delta": rounded(native_deltas["idle_ms"]),
        "backpressure_ms_delta": rounded(native_deltas["backpressure_ms"]),
        "busy_ratio": rounded(busy_ratio),
        "idle_ratio": rounded(idle_ratio),
        "backpressure_ratio": rounded(backpressure_ratio),
        "fired_timers_delta": rounded(native_deltas["fired_timers"]),
        "is_backpressured": to_bool(current_metrics.get("isBackPressured")),
        "mailbox_queue_size": rounded(exact_metric(current_metrics, "mailboxQueueSize")),
        "window_statistics": window_statistics,
        "source_metrics": source_metrics,
    }



def build_intervals(
    snapshots: list[dict[str, Any]], topology: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    topology_by_id = {operator["vertex_id"]: operator for operator in topology}
    topology_order = {
        operator["vertex_id"]: operator["order"] for operator in topology
    }

    intervals: list[dict[str, Any]] = []

    for interval_id, (previous_snapshot, current_snapshot) in enumerate(
        zip(snapshots, snapshots[1:])
    ):
        start_ms = int(previous_snapshot["timestamp_ms"])
        end_ms = int(current_snapshot["timestamp_ms"])
        duration_ms = end_ms - start_ms

        previous_subtasks = snapshot_subtasks(previous_snapshot)
        current_subtasks = snapshot_subtasks(current_snapshot)
        keys = set(previous_subtasks) | set(current_subtasks)
        keys = sorted(
            keys,
            key=lambda key: (
                topology_order.get(key[0], len(topology_order)),
                key[1],
                key[0],
            ),
        )

        subtask_intervals = [
            build_subtask_interval(
                previous_subtasks.get(key),
                current_subtasks.get(key),
                topology_by_id.get(key[0]),
                key[0],
                key[1],
                duration_ms,
            )
            for key in keys
        ]

        intervals.append(
            {
                "interval_id": interval_id,
                "start_snapshot_id": previous_snapshot.get("snapshot_id"),
                "end_snapshot_id": current_snapshot.get("snapshot_id"),
                "start_timestamp_ms": start_ms,
                "end_timestamp_ms": end_ms,
                "duration_ms": duration_ms,
                "phase": "UNCLASSIFIED",
                "stable": False,
                "regime": "UNKNOWN",
                "baseline_eligible": False,
                "source_records_out_delta": None,
                "source_throughput_records_per_second": None,
                "source_smoothed_throughput_records_per_second": None,
                "source_rate_relative_error": None,
                "source_window_robust_cv": None,
                "configured_arrival_rate_records_per_second": None,
                "source_capacity_ratio": None,
                "configured_rate_satisfied": None,
                "max_source_busy_ratio": None,
                "saturation_reasons": [],
                "stable_operator_fraction": 0.0,
                "stable_state_fraction": 0.0,
                "max_backpressure_ratio": None,
                "subtasks": subtask_intervals,
            }
        )

    return intervals


# =============================================================================
# Source rate and stability
# =============================================================================
def trailing_window(intervals: list[dict[str, Any]], index: int) -> list[int]:
    minimum_timestamp = intervals[index]["end_timestamp_ms"] - SMOOTH_WINDOW_MS
    first = index

    while first > 0 and intervals[first]["start_timestamp_ms"] > minimum_timestamp:
        first -= 1

    return list(range(first, index + 1))


def add_source_rates(intervals: list[dict[str, Any]], source_ids: set[str]) -> None:
    for interval in intervals:
        source_deltas = [
            subtask["records_out_delta"]
            for subtask in interval["subtasks"]
            if subtask["vertex_id"] in source_ids
            and subtask["records_out_delta"] is not None
        ]

        if source_deltas:
            total = sum(float(value) for value in source_deltas)
            interval["source_records_out_delta"] = rounded(total)
            interval["source_throughput_records_per_second"] = rounded(
                total / (interval["duration_ms"] / 1000)
            )

    for index, interval in enumerate(intervals):
        rates = [
            intervals[position]["source_throughput_records_per_second"]
            for position in trailing_window(intervals, index)
            if intervals[position]["source_throughput_records_per_second"] is not None
            and intervals[position]["source_throughput_records_per_second"] > 0
        ]
        interval["source_smoothed_throughput_records_per_second"] = rounded(
            median([float(value) for value in rates])
        )



def downstream_progressed(interval: dict[str, Any], source_ids: set[str]) -> bool:
    """Return whether at least one non-source subtask progressed in the interval."""
    return any(
        subtask["vertex_id"] not in source_ids
        and (
            float(subtask["records_in_delta"] or 0) > 0
            or float(subtask["records_out_delta"] or 0) > 0
        )
        for subtask in interval["subtasks"]
    )


def detect_drain(
    intervals: list[dict[str, Any]], source_ids: set[str]
) -> tuple[Optional[int], str]:
    """Detect a confirmed trailing DRAIN sequence.

    A DRAIN candidate must be a suffix of the execution where:
      * source numRecordsOut does not increase in every interval;
      * downstream processing still progresses in at least one interval;
      * the suffix contains at least MIN_DRAIN_CONFIRMATION_INTERVALS; and
      * its observed duration is at least MIN_DRAIN_CONFIRMATION_MS.

    Returns:
        (drain_start_index, observation)

    observation is one of:
        OBSERVED, NOT_CONFIRMED, NOT_OBSERVED
    """
    if not intervals:
        return None, "NOT_OBSERVED"

    candidate_start = len(intervals)

    for index in range(len(intervals) - 1, -1, -1):
        source_delta = intervals[index]["source_records_out_delta"]
        if source_delta is None or float(source_delta) != 0.0:
            break
        candidate_start = index

    if candidate_start == len(intervals):
        return None, "NOT_OBSERVED"

    candidate_intervals = intervals[candidate_start:]
    candidate_duration_ms = (
        candidate_intervals[-1]["end_timestamp_ms"]
        - candidate_intervals[0]["start_timestamp_ms"]
    )
    downstream_activity = any(
        downstream_progressed(interval, source_ids)
        for interval in candidate_intervals
    )

    confirmed = bool(
        len(candidate_intervals) >= MIN_DRAIN_CONFIRMATION_INTERVALS
        and candidate_duration_ms >= MIN_DRAIN_CONFIRMATION_MS
        and downstream_activity
    )

    if confirmed:
        return candidate_start, "OBSERVED"

    return None, "NOT_CONFIRMED"


def source_reference_rate(
    intervals: list[dict[str, Any]], last_emission_index: Optional[int]
) -> Optional[float]:
    end = last_emission_index if last_emission_index is not None else len(intervals) - 1
    rates = [
        float(interval["source_smoothed_throughput_records_per_second"])
        for interval in intervals[: end + 1]
        if interval["source_smoothed_throughput_records_per_second"] is not None
        and interval["source_smoothed_throughput_records_per_second"] > 0
    ]

    if not rates:
        return None

    middle = statistics.median(rates)
    upper_half = [rate for rate in rates if rate >= middle]
    return float(statistics.median(upper_half or rates))


def interval_subtask_map(interval: dict[str, Any]) -> dict[tuple[str, int], dict[str, Any]]:
    return {
        (subtask["vertex_id"], int(subtask["subtask"])): subtask
        for subtask in interval["subtasks"]
    }


def classify_interval_stability(
    intervals: list[dict[str, Any]],
    reference_rate: Optional[float],
    drain_start_index: Optional[int],
) -> None:
    interval_maps = [interval_subtask_map(interval) for interval in intervals]

    for index, interval in enumerate(intervals):
        positions = trailing_window(intervals, index)
        coverage_ms = (
            interval["end_timestamp_ms"]
            - intervals[positions[0]]["start_timestamp_ms"]
        )

        source_rates = [
            float(intervals[position]["source_throughput_records_per_second"])
            for position in positions
            if intervals[position]["source_throughput_records_per_second"] is not None
            and intervals[position]["source_throughput_records_per_second"] > 0
        ]
        source_cv = robust_cv(source_rates)
        interval["source_window_robust_cv"] = rounded(source_cv)

        smoothed_rate = interval["source_smoothed_throughput_records_per_second"]
        rate_error = None
        if reference_rate and smoothed_rate is not None:
            rate_error = abs(float(smoothed_rate) - reference_rate) / reference_rate
        interval["source_rate_relative_error"] = rounded(rate_error)

        source_stable = bool(
            coverage_ms >= SMOOTH_WINDOW_MS
            and rate_error is not None
            and rate_error <= SOURCE_RATE_RELATIVE_TOLERANCE
            and source_cv is not None
            and source_cv <= SOURCE_RATE_ROBUST_CV_TOLERANCE
        )

        all_keys: set[tuple[str, int]] = set()
        for position in positions:
            all_keys.update(interval_maps[position])

        operator_flags: dict[tuple[str, int], bool] = {}
        state_flags: dict[tuple[str, int], bool] = {}

        for key in all_keys:
            means: list[float] = []
            busy: list[float] = []
            idle: list[float] = []
            backpressure: list[float] = []

            for position in positions:
                subtask = interval_maps[position].get(key)
                if not subtask:
                    continue

                if (
                    subtask["service_metrics_valid"]
                    and subtask["delta_samples"] is not None
                    and subtask["delta_samples"] >= MIN_SAMPLES_PER_INTERVAL
                    and subtask["mean_invocation_ns"] is not None
                ):
                    means.append(float(subtask["mean_invocation_ns"]))

                if subtask["state_metrics_valid"]:
                    busy.append(float(subtask["busy_ratio"]))
                    idle.append(float(subtask["idle_ratio"]))
                    backpressure.append(float(subtask["backpressure_ratio"]))

            if len(means) >= 2:
                cv = robust_cv(means)
                operator_flags[key] = bool(
                    cv is not None and cv <= OPERATOR_MEAN_ROBUST_CV_TOLERANCE
                )

            if len(busy) >= 2 and len(idle) >= 2 and len(backpressure) >= 2:
                state_flags[key] = bool(
                    max(busy) - min(busy) <= STATE_RATIO_ABSOLUTE_TOLERANCE
                    and max(idle) - min(idle) <= STATE_RATIO_ABSOLUTE_TOLERANCE
                    and max(backpressure) - min(backpressure)
                    <= STATE_RATIO_ABSOLUTE_TOLERANCE
                )

        stable_operator_fraction = (
            sum(operator_flags.values()) / len(operator_flags)
            if operator_flags
            else 0.0
        )
        stable_state_fraction = (
            sum(state_flags.values()) / len(state_flags) if state_flags else 0.0
        )

        interval["stable_operator_fraction"] = rounded(stable_operator_fraction)
        interval["stable_state_fraction"] = rounded(stable_state_fraction)

        for key, subtask in interval_maps[index].items():
            subtask["operator_stable"] = operator_flags.get(key, False)
            subtask["state_stable"] = state_flags.get(key, False)

        before_drain = drain_start_index is None or index < drain_start_index
        interval["stable"] = bool(
            before_drain
            and source_stable
            and operator_flags
            and stable_operator_fraction >= MIN_STABLE_OPERATOR_FRACTION
            and state_flags
            and stable_state_fraction >= MIN_STABLE_STATE_FRACTION
        )


def find_steady_start(
    intervals: list[dict[str, Any]], drain_start_index: Optional[int]
) -> Optional[int]:
    last_index = (
        drain_start_index - 1
        if drain_start_index is not None
        else len(intervals) - 1
    )
    run_start: Optional[int] = None

    for index in range(last_index + 1):
        if not intervals[index]["stable"]:
            run_start = None
            continue

        if run_start is None:
            run_start = index

        duration = (
            intervals[index]["end_timestamp_ms"]
            - intervals[run_start]["start_timestamp_ms"]
        )
        if duration >= STEADY_CONFIRMATION_MS:
            return run_start

    return None


# =============================================================================
# Phase, regime and baseline eligibility
# =============================================================================
def apply_classification(
    intervals: list[dict[str, Any]],
    topology: list[dict[str, Any]],
    source_ids: set[str],
    steady_start: Optional[int],
    drain_start_index: Optional[int],
    configured_arrival_rate: int,
) -> None:
    all_parallelism_one = all(operator["parallelism"] == 1 for operator in topology)

    for index, interval in enumerate(intervals):
        if drain_start_index is not None and index >= drain_start_index:
            interval["phase"] = "DRAIN"
        elif steady_start is not None and index >= steady_start:
            interval["phase"] = "STEADY"
        else:
            interval["phase"] = "WARMUP"

        backpressure = [
            float(subtask["backpressure_ratio"])
            for subtask in interval["subtasks"]
            if subtask["state_metrics_valid"]
            and subtask["backpressure_ratio"] is not None
        ]
        max_backpressure = max(backpressure) if backpressure else None
        interval["max_backpressure_ratio"] = rounded(max_backpressure)

        instantaneous_backpressure = any(
            subtask["is_backpressured"] is True for subtask in interval["subtasks"]
        )

        source_busy_ratios = [
            float(subtask["busy_ratio"])
            for subtask in interval["subtasks"]
            if subtask["vertex_id"] in source_ids
            and subtask["state_metrics_valid"]
            and subtask["busy_ratio"] is not None
        ]
        max_source_busy_ratio = (
            max(source_busy_ratios) if source_busy_ratios else None
        )
        interval["max_source_busy_ratio"] = rounded(max_source_busy_ratio)

        smoothed_rate = interval[
            "source_smoothed_throughput_records_per_second"
        ]
        capacity_ratio = (
            float(smoothed_rate) / configured_arrival_rate
            if smoothed_rate is not None
            else None
        )
        configured_rate_satisfied = (
            capacity_ratio is not None
            and capacity_ratio >= CONFIGURED_RATE_SATISFACTION_RATIO
        )

        interval["configured_arrival_rate_records_per_second"] = (
            configured_arrival_rate
        )
        interval["source_capacity_ratio"] = rounded(capacity_ratio)
        interval["configured_rate_satisfied"] = configured_rate_satisfied

        backpressure_saturated = bool(
            instantaneous_backpressure
            or (
                max_backpressure is not None
                and max_backpressure > BASELINE_MAX_BACKPRESSURE_RATIO
            )
        )
        rate_limited = bool(
            capacity_ratio is not None
            and capacity_ratio < CONFIGURED_RATE_SATISFACTION_RATIO
        )
        source_capacity_limited = bool(
            rate_limited
            and max_source_busy_ratio is not None
            and max_source_busy_ratio >= SOURCE_BUSY_SATURATION_THRESHOLD
        )

        saturation_reasons: list[str] = []
        if backpressure_saturated:
            saturation_reasons.append("BACKPRESSURE")
        if rate_limited:
            saturation_reasons.append("CONFIGURED_RATE_NOT_REACHED")
        if source_capacity_limited:
            saturation_reasons.append("SOURCE_BUSY_NEAR_CAPACITY")

        interval["saturation_reasons"] = saturation_reasons

        # Regime classification is only meaningful after temporal stabilization.
        if interval["phase"] != "STEADY":
            interval["regime"] = "UNKNOWN"
        elif backpressure_saturated or source_capacity_limited:
            interval["regime"] = "SATURATED"
        elif configured_rate_satisfied:
            # INTERFERENCE requires comparison against a separate P=1 baseline.
            interval["regime"] = "UNSATURATED"
        else:
            interval["regime"] = "UNKNOWN"

        rate_error = interval["source_rate_relative_error"]
        interval["baseline_eligible"] = bool(
            all_parallelism_one
            and interval["phase"] == "STEADY"
            and interval["stable"]
            and interval["regime"] == "UNSATURATED"
            and configured_rate_satisfied
            and max_backpressure is not None
            and max_backpressure <= BASELINE_MAX_BACKPRESSURE_RATIO
            and rate_error is not None
            and rate_error <= SOURCE_RATE_RELATIVE_TOLERANCE
        )

        for subtask in interval["subtasks"]:
            subtask["baseline_eligible"] = bool(
                interval["baseline_eligible"]
                and subtask["service_metrics_valid"]
                and subtask["operator_stable"]
            )


def classify(
    intervals: list[dict[str, Any]],
    topology: list[dict[str, Any]],
    request_count: int,
    configured_arrival_rate: int,
) -> dict[str, Any]:
    warnings: list[str] = []
    source_ids = detect_source_vertices(topology)
    source_id_set = set(source_ids)

    add_source_rates(intervals, source_id_set)

    emission_intervals = [
        index
        for index, interval in enumerate(intervals)
        if interval["source_records_out_delta"] is not None
        and interval["source_records_out_delta"] > 0
    ]
    last_emission_index = emission_intervals[-1] if emission_intervals else None

    drain_start_index, drain_observation = detect_drain(
        intervals, source_id_set
    )
    drain_detected = drain_start_index is not None

    if not source_ids:
        warnings.append("No source vertex could be inferred from subtask_topology.txt.")
    if last_emission_index is None:
        warnings.append("No positive source numRecordsOut delta was found.")

    if drain_observation == "NOT_CONFIRMED":
        warnings.append(
            "A final DRAIN candidate was found, but it did not satisfy the "
            "minimum interval count, duration, and downstream-progress rules."
        )
    elif drain_observation == "NOT_OBSERVED":
        warnings.append(
            "DRAIN was not observed; the source may have emitted until job "
            "completion or the drain duration may have been shorter than the "
            "snapshot interval."
        )

    reference_rate = source_reference_rate(intervals, last_emission_index)
    if reference_rate is None:
        warnings.append("The source reference throughput could not be estimated.")

    classify_interval_stability(intervals, reference_rate, drain_start_index)
    steady_start = find_steady_start(intervals, drain_start_index)

    if steady_start is None:
        warnings.append("No sustained STEADY region satisfied the stability rules.")

    apply_classification(
        intervals,
        topology,
        source_id_set,
        steady_start,
        drain_start_index,
        configured_arrival_rate,
    )

    steady_start_timestamp = None
    steady_end_timestamp = None
    steady_duration_ms = 0

    if steady_start is not None:
        steady_end_index = (
            drain_start_index - 1
            if drain_start_index is not None
            else len(intervals) - 1
        )
        steady_start_timestamp = intervals[steady_start]["start_timestamp_ms"]
        steady_end_timestamp = intervals[steady_end_index]["end_timestamp_ms"]
        steady_duration_ms = steady_end_timestamp - steady_start_timestamp

        if steady_duration_ms < MIN_STEADY_DURATION_MS:
            warnings.append(
                f"STEADY lasts {steady_duration_ms} ms, below the recommended "
                f"minimum of {MIN_STEADY_DURATION_MS} ms."
            )

    drain_start_timestamp = (
        intervals[drain_start_index]["start_timestamp_ms"]
        if drain_start_index is not None
        else None
    )
    drain_interval_count = (
        len(intervals) - drain_start_index
        if drain_start_index is not None
        else 0
    )
    drain_duration_ms = (
        intervals[-1]["end_timestamp_ms"]
        - intervals[drain_start_index]["start_timestamp_ms"]
        if drain_start_index is not None
        else 0
    )

    reference_capacity_ratio = (
        reference_rate / configured_arrival_rate
        if reference_rate is not None
        else None
    )

    steady_regime_counts: dict[str, int] = {}
    for interval in intervals:
        if interval["phase"] != "STEADY":
            continue
        regime = str(interval["regime"])
        steady_regime_counts[regime] = steady_regime_counts.get(regime, 0) + 1

    return {
        "configured_request_count": request_count,
        "configured_arrival_rate_records_per_second": configured_arrival_rate,
        "source_vertex_ids": source_ids,
        "source_reference_rate_records_per_second": rounded(reference_rate),
        "source_reference_capacity_ratio": rounded(reference_capacity_ratio),
        "last_source_emission_interval_id": (
            intervals[last_emission_index]["interval_id"]
            if last_emission_index is not None
            else None
        ),
        "drain_detected": drain_detected,
        "drain_observation": drain_observation,
        "drain_start_interval_id": (
            intervals[drain_start_index]["interval_id"]
            if drain_start_index is not None
            else None
        ),
        "drain_start_timestamp_ms": drain_start_timestamp,
        "drain_interval_count": drain_interval_count,
        "drain_duration_ms": drain_duration_ms,
        "steady_detected": steady_start is not None,
        "steady_start_interval_id": (
            intervals[steady_start]["interval_id"] if steady_start is not None else None
        ),
        "steady_start_timestamp_ms": steady_start_timestamp,
        "steady_end_timestamp_ms": steady_end_timestamp,
        "steady_duration_ms": steady_duration_ms,
        "steady_duration_sufficient": steady_duration_ms >= MIN_STEADY_DURATION_MS,
        "steady_regime_counts": steady_regime_counts,
        "all_parallelism_one": all(
            operator["parallelism"] == 1 for operator in topology
        ),
        "warnings": warnings,
    }


# =============================================================================
# Output
# =============================================================================
def write_output(
    snapshots: list[dict[str, Any]],
    intervals: list[dict[str, Any]],
    classification: dict[str, Any],
) -> None:
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    output = {
        "metadata": {
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "snapshots_file": str(SNAPSHOTS_FILE),
            "operators_file": str(OPERATORS_FILE),
            "snapshot_count": len(snapshots),
            "interval_count": len(intervals),
            **classification,
            "thresholds": {
                "smooth_window_ms": SMOOTH_WINDOW_MS,
                "steady_confirmation_ms": STEADY_CONFIRMATION_MS,
                "minimum_steady_duration_ms": MIN_STEADY_DURATION_MS,
                "source_rate_relative_tolerance": SOURCE_RATE_RELATIVE_TOLERANCE,
                "source_rate_robust_cv_tolerance": SOURCE_RATE_ROBUST_CV_TOLERANCE,
                "operator_mean_robust_cv_tolerance": OPERATOR_MEAN_ROBUST_CV_TOLERANCE,
                "minimum_stable_operator_fraction": MIN_STABLE_OPERATOR_FRACTION,
                "minimum_samples_per_interval": MIN_SAMPLES_PER_INTERVAL,
                "state_ratio_absolute_tolerance": STATE_RATIO_ABSOLUTE_TOLERANCE,
                "minimum_stable_state_fraction": MIN_STABLE_STATE_FRACTION,
                "baseline_max_backpressure_ratio": BASELINE_MAX_BACKPRESSURE_RATIO,
                "configured_rate_satisfaction_ratio": CONFIGURED_RATE_SATISFACTION_RATIO,
                "source_busy_saturation_threshold": SOURCE_BUSY_SATURATION_THRESHOLD,
                "minimum_drain_confirmation_intervals": MIN_DRAIN_CONFIRMATION_INTERVALS,
                "minimum_drain_confirmation_ms": MIN_DRAIN_CONFIRMATION_MS,
            },
        },
        "intervals": intervals,
    }

    with OUTPUT_FILE.open("w", encoding="utf-8") as file:
        json.dump(output, file, indent=2, ensure_ascii=False, allow_nan=False)
        file.write("\n")


def main() -> None:
    if len(sys.argv) != 3:
        abort(
            f"usage: {Path(sys.argv[0]).name} "
            "<request_count> <arrival_rate_records_per_second>"
        )

    request_count = positive_integer_argument(sys.argv[1], "request_count")
    configured_arrival_rate = positive_integer_argument(
        sys.argv[2], "arrival_rate_records_per_second"
    )

    topology = load_topology()
    snapshots = load_snapshots()
    intervals = build_intervals(snapshots, topology)
    classification = classify(
        intervals,
        topology,
        request_count,
        configured_arrival_rate,
    )
    write_output(snapshots, intervals, classification)

    print(f"Generated intervals: {len(intervals)}")
    print(f"Configured requests: {request_count}")
    print(
        "Configured arrival rate: "
        f"{configured_arrival_rate} records/s"
    )
    print(
        "Source reference rate: "
        f"{classification['source_reference_rate_records_per_second']} records/s"
    )
    print(
        "Source reference capacity ratio: "
        f"{classification['source_reference_capacity_ratio']}"
    )
    print(f"STEADY detected: {classification['steady_detected']}")
    print(f"STEADY duration: {classification['steady_duration_ms']} ms")
    print(
        "STEADY regime counts: "
        f"{classification['steady_regime_counts']}"
    )
    print(f"DRAIN detected: {classification['drain_detected']}")
    print(f"DRAIN observation: {classification['drain_observation']}")

    for warning in classification["warnings"]:
        print(f"Warning: {warning}", file=sys.stderr)

    print(f"Intervals exported to: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()