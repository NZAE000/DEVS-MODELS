#!/usr/bin/env python3
import os
import sys
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from collections import OrderedDict

plt.style.use("metrics/thesis.mplstyle")

BASE_DIR = "metrics/nexmark/utilization"
THROUGHPUT_BASE_DIR = "metrics/nexmark/throughput"


def read_util_file(path):
    """
    Read a utilization file with lines of the form:
      operA:0.123;operB:0.456;...;
    Preserve the operator order as it appears in the file.
    """
    op_values = OrderedDict()

    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            pairs = [p for p in line.split(";") if p]

            for pair in pairs:
                if ":" not in pair:
                    continue

                name, val = pair.split(":", 1)

                try:
                    value = float(val)
                except ValueError:
                    continue

                if name not in op_values:
                    op_values[name] = []

                op_values[name].append(value)

    return op_values


def mean_per_operator(op_values):
    """Return the average utilization for each operator preserving order."""
    return OrderedDict(
        (op, float(np.mean(vals)) if vals else 0.0)
        for op, vals in op_values.items()
    )


def read_throughput_file(path):
    """
    Read a throughput file with lines of the form:
      finish_time throughput
    Return the average finish time and throughput.
    """
    finish_times = []
    throughputs = []

    with open(path, "r") as f:
        for line in f:
            parts = line.strip().split()

            if len(parts) == 2:
                try:
                    finish_time, throughput = map(float, parts)
                except ValueError:
                    continue

                finish_times.append(finish_time)
                throughputs.append(throughput)

    if not finish_times or not throughputs:
        return None, None

    return float(np.mean(finish_times)), float(np.mean(throughputs))


def parse_identifier_from_filename(filename, appname, data_from):
    """
    Convert:
      terminated-utilization-real-q3-1-32-1-100000-5000.txt
    or:
      terminated-utilization-sim-q3-1-32-1-100000-5000.txt
    to:
      1-32-1-100000-5000
    """
    base = filename.replace(".txt", "")
    base = base.replace(f"terminated-utilization-{data_from}-", "")

    if base.startswith(appname + "-"):
        return base[len(appname) + 1:]

    parts = base.split("-", 1)
    return parts[1] if len(parts) > 1 else base


def main():
    if len(sys.argv) < 7:
        print(
            "Use: python utilization_plot_by_parallelism.py "
            "<app> <nodes> <cores> <events> <arrival> <real|sim>"
        )
        print(
            "e.g: python utilization_plot_by_parallelism.py "
            "q3 1 32 100000 5000 real"
        )
        sys.exit(1)

    app = sys.argv[1]
    nodes = sys.argv[2]
    cores = sys.argv[3]
    events = sys.argv[4]
    arrival = sys.argv[5]
    data_from = sys.argv[6].lower()

    # Validate data source
    if data_from not in ("real", "sim"):
        print("The last parameter must be 'real' or 'sim'.")
        sys.exit(1)

    # Select input directories
    input_dir = os.path.join(BASE_DIR, data_from, "terminated")
    throughput_dir = os.path.join(
        THROUGHPUT_BASE_DIR,
        data_from,
        "terminated"
    )

    if not os.path.isdir(input_dir):
        print(f"Directory not found: {input_dir}")
        sys.exit(1)

    if not os.path.isdir(throughput_dir):
        print(f"Directory not found: {throughput_dir}")
        sys.exit(1)

    # Capture matching utilization scenarios
    prefix_filename = f"terminated-utilization-{data_from}-{app}"

    files = [
        f for f in os.listdir(input_dir)
        if f.startswith(prefix_filename) and f.endswith(".txt")
    ]

    prefix_scenario = f"{nodes}-{cores}-"
    scenario_map = {}

    for f in files:
        ident = parse_identifier_from_filename(f, app, data_from)

        if (
            ident.startswith(prefix_scenario)
            and ident.endswith(f"{events}-{arrival}")
        ):
            scenario_map[ident] = f

    if not scenario_map:
        print(
            f"No {data_from.upper()} files were found "
            "for that configuration."
        )
        sys.exit(1)

    # Sort scenarios by parallelism
    scenario_ids = sorted(
        scenario_map.keys(),
        key=lambda x: int(x.split("-")[2])
    )

    parallelism_levels = [
        int(ident.split("-")[2])
        for ident in scenario_ids
    ]

    # Compute average utilization per operator and parallelism level
    stats = OrderedDict()
    operator_order = None
    operator_set = None

    for ident in scenario_ids:
        filepath = os.path.join(input_dir, scenario_map[ident])
        op_values = read_util_file(filepath)
        means = mean_per_operator(op_values)

        if not means:
            print(f"No valid utilization values found in: {filepath}")
            sys.exit(1)

        current_operators = set(means.keys())

        if operator_set is None:
            operator_set = current_operators
            operator_order = list(means.keys())
        elif current_operators != operator_set:
            missing_ops = operator_set - current_operators
            new_ops = current_operators - operator_set

            print(f"ERROR: The operator set changed in scenario {ident}.")

            if missing_ops:
                print("Missing operators:", ", ".join(missing_ops))

            if new_ops:
                print("New operators:", ", ".join(new_ops))

            sys.exit(1)

        stats[ident] = means

    # Preserve the operator order from the utilization records
    operators = operator_order

    # Build one utilization series per operator
    op_series = {op: [] for op in operators}

    for ident in scenario_ids:
        for op in operators:
            op_series[op].append(stats[ident][op])

    # Plot
    plt.figure()

    cmap = plt.get_cmap("tab20")
    base_colors = [
        cmap(i % cmap.N)
        for i in range(len(operators))
    ]

    for i, op in enumerate(operators):
        plt.plot(
            parallelism_levels,
            op_series[op],
            color=base_colors[i],
            marker="o",
            label=op
        )

    plt.title(
        f"Operator utilization - {app}\n"
        f"{nodes} nodes, {cores} cores, reqs={events}, rate={arrival}"
    )
    plt.xlabel("Parallelism level")
    plt.ylabel("Utilization")
    plt.xticks(parallelism_levels)
    plt.grid(True)

    # Build operator legend
    ax = plt.gca()
    operator_handles = []

    for i, op in enumerate(operators):
        color = base_colors[i]

        operator_handles.append(
            Line2D(
                [0],
                [0],
                marker="s",
                linestyle="None",
                markerfacecolor=color,
                markeredgecolor=color,
                markersize=8,
                label=op
            )
        )

    legend_ops = ax.legend(
        handles=operator_handles,
        loc="upper center",
        bbox_to_anchor=(0.5, -0.15),
        ncol=min(4, len(operators))
    )

    plt.subplots_adjust(bottom=0.3)

    # Export plot to PDF and PNG files
    out_dir = os.path.join(
        BASE_DIR,
        f"plot-{data_from}",
        "terminated"
    )

    os.makedirs(out_dir, exist_ok=True)

    out_name = (
        f"terminated-utilization-{data_from}-"
        f"{app}-{nodes}-{cores}-{events}-{arrival}"
    )

    out_path = os.path.join(out_dir, out_name)

    plt.savefig(
        f"{out_path}.pdf",
        bbox_extra_artists=(legend_ops,),
        bbox_inches="tight"
    )

    plt.savefig(
        f"{out_path}.png",
        bbox_extra_artists=(legend_ops,),
        bbox_inches="tight"
    )

    # Print time, throughput, accumulated busy time, busy time and utilization
    print()

    for ident, p in zip(scenario_ids, parallelism_levels):
        throughput_filename = (
            f"terminated-throughput-{data_from}-"
            f"{app}-{nodes}-{cores}-{p}-{events}-{arrival}.txt"
        )

        throughput_path = os.path.join(
            throughput_dir,
            throughput_filename
        )

        if not os.path.isfile(throughput_path):
            print(f"Throughput file not found: {throughput_path}")
            sys.exit(1)

        time_avg, throughput_avg = read_throughput_file(
            throughput_path
        )

        if time_avg is None or throughput_avg is None:
            print(
                f"No valid throughput values found in: "
                f"{throughput_path}"
            )
            sys.exit(1)

        print(f"P={p}")
        print(
            f"{'Time (s)':<20}"
            f"{'Throughput (req/s)':<20}"
        )
        print(
            f"{time_avg:<20.6f}"
            f"{throughput_avg:<20.6g}"
        )
        print()

        print(
            f"{'Operator':<28}"
            f"{'P':<6}"
            f"{'AccumBusyTime':<18}"
            f"{'BusyTime':<18}"
            f"{'Utilization':<18}"
        )

        for op in operators:
            utilization = stats[ident][op]
            busy_time = utilization * time_avg
            accum_busy_time = busy_time * p

            print(
                f"{op:<28}"
                f"{p:<6}"
                f"{accum_busy_time:<18.9g}"
                f"{busy_time:<18.9g}"
                f"{utilization:<18.9g}"
            )

        print()

    plt.show()


if __name__ == "__main__":
    main()