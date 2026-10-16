import os
import sys
import numpy as np
from matplotlib.lines import Line2D
import matplotlib.pyplot as plt

plt.style.use("metrics/thesis.mplstyle")

# Paths
BASE_DIR = "metrics/nexmark/utilization"
THROUGHPUT_BASE_DIR = "metrics/nexmark/throughput"


# -------------------- Load Utilization File --------------------

def load_util_file(path):
    """
    Read lines:
      op1:val1;op2:val2;...

    Returns a list of dictionaries:
      [{op: val, ...}, ...]
    """
    results = []

    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            d = {}

            for entry in line.split(";"):
                if ":" not in entry:
                    continue

                op, val = entry.split(":", 1)

                try:
                    d[op] = float(val)
                except ValueError:
                    continue

            if d:
                results.append(d)

    return results


# -------------------- Load Throughput File --------------------

def load_throughput_file(path):
    """
    Read lines:
      finish_time throughput

    Returns:
      finish_times, throughputs
    """
    finish_times = []
    throughputs = []

    with open(path, "r") as f:
        for line in f:
            parts = line.strip().split()

            if len(parts) != 2:
                continue

            try:
                finish_time = float(parts[0])
                throughput = float(parts[1])
            except ValueError:
                continue

            finish_times.append(finish_time)
            throughputs.append(throughput)

    return finish_times, throughputs


# -------------------- Parse Scenario Identifier --------------------

def parse_identifier(filename, app, data_from, metric):
    """
    File name:
      terminated-utilization-real-q3-1-32-1-100000-5000.txt
      terminated-throughput-real-q3-1-32-1-100000-5000.txt

    Return:
      (nodes, cores, parallelism, events, arrival)
    """
    prefix = f"terminated-{metric}-{data_from}-{app}-"
    base = filename.replace(".txt", "").replace(prefix, "")
    parts = base.split("-")

    if len(parts) != 5:
        raise ValueError(f"Invalid name: {filename}")

    nodes, cores, par, events, arrival = parts
    return int(nodes), int(cores), int(par), int(events), int(arrival)


# -------------------- Main --------------------

def main():
    if len(sys.argv) != 6:
        print(
            "Use: python terminated_utilization_plot_by_events-rate.py "
            "<app> <nodes> <cores> <parallelism> <real|sim>"
        )
        print(
            "e.g: python terminated_utilization_plot_by_events-rate.py "
            "q3 1 32 1 real"
        )
        return

    app = sys.argv[1]
    nodes = int(sys.argv[2])
    cores = int(sys.argv[3])
    par = int(sys.argv[4])
    data_from = sys.argv[5].lower()

    # Validate data source
    if data_from not in ("real", "sim"):
        print("The last parameter must be 'real' or 'sim'.")
        sys.exit(1)

    # Select input directories
    input_dir = os.path.join(BASE_DIR, data_from, "terminated")
    throughput_dir = os.path.join(THROUGHPUT_BASE_DIR, data_from, "terminated")

    if not os.path.isdir(input_dir):
        print(f"Directory not found: {input_dir}")
        sys.exit(1)

    if not os.path.isdir(throughput_dir):
        print(f"Directory not found: {throughput_dir}")
        sys.exit(1)

    # Search utilization files for the specific configuration
    files = []

    for fname in os.listdir(input_dir):
        if fname.startswith(f"terminated-utilization-{data_from}-{app}"):
            try:
                n, c, p, ev, ar = parse_identifier(
                    fname, app, data_from, "utilization"
                )

                if n == nodes and c == cores and p == par:
                    files.append((ev, ar, fname))
            except ValueError:
                continue

    if not files:
        print(
            f"No {data_from.upper()} files were found "
            "for that configuration."
        )
        return

    # Convert utilization files to dictionary indexed by scenario
    scenario_dict = {
        (ev, ar): fn
        for ev, ar, fn in files
    }

    # Order scenarios by arrival rate
    scenarios = sorted(
        scenario_dict.keys(),
        key=lambda x: x[1]
    )

    # Process utilization and throughput files
    avg_values = {}
    workload_stats = {}
    operators = None

    for ev, ar in scenarios:
        util_path = os.path.join(
            input_dir,
            scenario_dict[(ev, ar)]
        )

        throughput_filename = (
            f"terminated-throughput-{data_from}-"
            f"{app}-{nodes}-{cores}-{par}-{ev}-{ar}.txt"
        )

        throughput_path = os.path.join(
            throughput_dir,
            throughput_filename
        )

        if not os.path.isfile(throughput_path):
            print(f"Throughput file not found: {throughput_path}")
            sys.exit(1)

        runs = load_util_file(util_path)
        finish_times, throughputs = load_throughput_file(throughput_path)

        if not runs:
            print(
                f"No valid utilization values found for "
                f"events={ev}, arrival={ar}"
            )
            sys.exit(1)

        if not finish_times or not throughputs:
            print(
                f"No valid throughput values found for "
                f"events={ev}, arrival={ar}"
            )
            sys.exit(1)

        # Each utilization line and throughput line must represent the same run
        if len(runs) != len(finish_times):
            print(
                f"ERROR: Different number of executions for "
                f"events={ev}, arrival={ar}: "
                f"utilization={len(runs)}, throughput={len(finish_times)}"
            )
            sys.exit(1)

        current_ops = set(runs[0].keys())

        if operators is None:
            # Preserve operator order from the utilization file
            operators = list(runs[0].keys())
        elif current_ops != set(operators):
            print(
                f"ERROR: The operator set changed in scenario "
                f"events={ev}, arrival={ar}"
            )
            print(" Missing operators:", set(operators) - current_ops)
            print(" New operators:", current_ops - set(operators))
            sys.exit(1)

        # Verify operator consistency across all executions
        for i, run in enumerate(runs):
            if set(run.keys()) != set(operators):
                print(
                    f"ERROR: The operator set changed in execution {i + 1} "
                    f"for events={ev}, arrival={ar}"
                )
                sys.exit(1)

        # Average utilization used for plotting
        avg_values[(ev, ar)] = {
            op: float(np.mean([run[op] for run in runs]))
            for op in operators
        }

        # Calculate per-run BusyTime and AccumBusyTime before averaging
        operator_stats = {}

        for op in operators:
            utilizations = [
                run[op]
                for run in runs
            ]

            busy_times = [
                util * ftime
                for util, ftime in zip(utilizations, finish_times)
            ]

            accum_busy_times = [
                busy_time * par
                for busy_time in busy_times
            ]

            operator_stats[op] = {
                "utilization": float(np.mean(utilizations)),
                "busy_time": float(np.mean(busy_times)),
                "accum_busy_time": float(np.mean(accum_busy_times))
            }

        workload_stats[(ev, ar)] = {
            "ftime": float(np.mean(finish_times)),
            "throughput": float(np.mean(throughputs)),
            "operators": operator_stats
        }

    # Build series for plotting
    x_labels = [
        f"{ev}\n{ar}"
        for ev, ar in scenarios
    ]

    x_pos = list(range(len(scenarios)))
    op_series = {op: [] for op in operators}

    for scen in scenarios:
        for op in operators:
            op_series[op].append(
                avg_values[scen][op]
            )

    # Plot
    plt.figure()

    cmap = plt.get_cmap("tab20")
    base_colors = [
        cmap(i % cmap.N)
        for i in range(len(operators))
    ]

    for i, op in enumerate(operators):
        plt.plot(
            x_pos,
            op_series[op],
            label=op,
            color=base_colors[i],
            marker="o"
        )

    plt.title(
        f"Operator utilization - {app}\n"
        f"{nodes} nodes, {cores} cores, parallelism={par}"
    )
    plt.xlabel("Events — Arrival Rate")
    plt.ylabel("Utilization")
    plt.xticks(x_pos, x_labels, rotation=25, fontsize=16)
    plt.grid(True)

    # Build operator legend
    ax = plt.gca()
    operator_handles = []

    for i, op in enumerate(operators):
        color = base_colors[i]

        operator_handles.append(
            Line2D(
                [0], [0],
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
        bbox_to_anchor=(0.5, -0.25),
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
        f"{app}-{nodes}-{cores}-{par}"
    )

    out_path = os.path.join(
        out_dir,
        out_name
    )

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

    # Print workload statistics
    print()

    for ev, ar in scenarios:
        stats = workload_stats[(ev, ar)]

        print(f"Req: {ev} Rate: {ar}")
        print()
        print(
            f"FTime: {stats['ftime']:.4f} s, "
            f"Throughput: {stats['throughput']:.4f} req/s"
        )
        print()

        print(
            f"{'Operator':<28}"
            f"{'AccumBusyTime':<20}"
            f"{'BusyTime':<20}"
            f"{'Utilization':<20}"
        )

        for op in operators:
            op_stats = stats["operators"][op]

            print(
                f"{op:<28}"
                f"{op_stats['accum_busy_time']:<20.6f}"
                f"{op_stats['busy_time']:<20.6f}"
                f"{op_stats['utilization']:<20.20f}"
            )

        print()

    plt.show()


if __name__ == "__main__":
    main()