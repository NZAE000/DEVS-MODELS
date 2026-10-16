import os
import sys
import numpy as np
import matplotlib.pyplot as plt

plt.style.use("metrics/thesis.mplstyle")

BASE_DIR = "metrics/nexmark/throughput"


def load_data(filepath):
    """Load finish time and throughput values from file: finishtime throughput"""
    finish_times = []
    throughputs = []

    with open(filepath, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                finish_time, throughput = parts
                finish_times.append(float(finish_time))
                throughputs.append(float(throughput))

    return finish_times, throughputs


def parse_params(filename):
    """
    Convert:
        terminated-throughput-sim-q2-1-32-3-1000000-10000000.txt
    to:
        (app, nodes, cores, parallelism, events, arrival)
    """
    name = filename.replace(".txt", "")
    parts = name.split("-")

    return (
        parts[3],          # app
        int(parts[4]),     # nodes
        int(parts[5]),     # cores
        int(parts[6]),     # parallelism
        int(parts[7]),     # events
        int(parts[8])      # arrival
    )


def main():
    if len(sys.argv) < 7:
        print(
            "Use: python throughput_plot_by_parallelism.py "
            "<app> <nodes> <cores> <events> <rate> <real|sim>"
        )
        sys.exit(1)

    app = sys.argv[1]
    nodes = int(sys.argv[2])
    cores = int(sys.argv[3])
    events = int(sys.argv[4])
    arrival = int(sys.argv[5])
    data_from = sys.argv[6].lower()

    # Validate data source
    if data_from not in ("real", "sim"):
        print("The last parameter must be 'real' or 'sim'.")
        sys.exit(1)

    # Select input directory
    input_dir = os.path.join(BASE_DIR, data_from, "terminated")

    if not os.path.isdir(input_dir):
        print(f"Directory not found: {input_dir}")
        sys.exit(1)

    # Capture matching scenarios
    prefix = f"terminated-throughput-{data_from}-{app}"
    files = [
        f for f in os.listdir(input_dir)
        if f.startswith(prefix) and f.endswith(".txt")
    ]

    matches = {}

    for f in files:
        file_app, n, c, p, e, a = parse_params(f)

        if file_app == app and n == nodes and c == cores and e == events and a == arrival:
            matches[p] = f

    if not matches:
        print(f"No {data_from.upper()} scenarios were found with those parameters.")
        sys.exit(1)

    # Sort available parallelism levels
    parallelism_levels = sorted(matches.keys())

    # Calculate average finish time and throughput
    finish_time_avg = []
    throughput_avg = []

    for p in parallelism_levels:
        filepath = os.path.join(input_dir, matches[p])
        finish_times, throughputs = load_data(filepath)

        if not finish_times or not throughputs:
            print(f"No valid values found in: {filepath}")
            sys.exit(1)

        finish_time_avg.append(np.mean(finish_times))
        throughput_avg.append(np.mean(throughputs))

    # Plot throughput by parallelism
    plt.figure()

    label = "Real" if data_from == "real" else "Simulated"
    color = "blue" if data_from == "real" else "red"

    plt.plot(
        parallelism_levels,
        throughput_avg,
        marker="o",
        color=color,
        label=label
    )

    plt.title(
        f"Throughput - {app}\n"
        f"{nodes} nodes, {cores} cores, reqs={events}, rate={arrival}"
    )
    plt.xlabel("Parallelism operator level")
    plt.ylabel("Throughput")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()

    # Export plot to PDF and PNG files
    out_dir = os.path.join(BASE_DIR, f"plot-{data_from}", "terminated")
    os.makedirs(out_dir, exist_ok=True)

    out_name = (
        f"terminated-throughput-{data_from}-"
        f"{app}-{nodes}-{cores}-{events}-{arrival}"
    )
    out_path = os.path.join(out_dir, out_name)

    plt.savefig(f"{out_path}.pdf")
    plt.savefig(f"{out_path}.png")

    # Print average finish time and throughput for each parallelism level
    print("\nAverage values by parallelism:\n")

    for p, time_avg, tp_avg in zip(
        parallelism_levels,
        finish_time_avg,
        throughput_avg
    ):
        print(f"P={p}")
        print(f"{time_avg} {tp_avg}\n")

    plt.show()


if __name__ == "__main__":
    main()