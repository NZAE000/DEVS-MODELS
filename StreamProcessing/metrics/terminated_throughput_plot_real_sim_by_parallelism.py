import os
import sys
import numpy as np
import matplotlib.pyplot as plt

plt.style.use("metrics/thesis.mplstyle")

BASE_DIR = "metrics/nexmark/throughput"
REAL_DIR = os.path.join(BASE_DIR, "real/terminated")
SIM_DIR  = os.path.join(BASE_DIR, "sim/terminated")


def load_data(filepath):
    """File upload throughput: finishtime throughput"""
    throughputs = []
    with open(filepath, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                _, tp = parts
                throughputs.append(float(tp))
    return throughputs


def parse_params(filename, app):
    """
    Convert:
        terminated-throughput-sim-q2-1-32-3-1000000-10000000.txt
    a:
        (app, nodes, cores, paralelismo, events, arrival)
    """
    name = filename.replace(".txt", "")
    parts = name.split("-")
    # parts = [q2, throughput, nodes, cores, paralelismo, events, arrival]
    return (
        parts[3],                     # app
        int(parts[4]),                # nodes
        int(parts[5]),                # cores
        int(parts[6]),                # parallelism
        int(parts[7]),                # events
        int(parts[8])                 # arrival
    )


def main():
    if len(sys.argv) < 6:
        print("Use: python throughput_plot_real_sim_by_parallelism.py <app> <nodes> <cores> <events> <rate>")
        sys.exit(1)

    app     = sys.argv[1]
    nodes   = int(sys.argv[2])
    cores   = int(sys.argv[3])
    events  = int(sys.argv[4])
    arrival = int(sys.argv[5])

    # -----------------------------
    # Capturing REAL scenarios
    # -----------------------------
    real_files = [
        f for f in os.listdir(REAL_DIR)
        if f.startswith("terminated-throughput-real-" + app)
    ]

    real_matches = {}

    for f in real_files:
        (app, n, c, p, e, a) = parse_params(f, app)

        if (n == nodes and c == cores and e == events and a == arrival):
            real_matches[p] = f  # key = paralelismo

    if not real_matches:
        print("No REAL scenarios were found with those parameters.")
        sys.exit(1)

    # -----------------------------
    # Capture simulated scenarios
    # -----------------------------
    sim_files = [
        f for f in os.listdir(SIM_DIR)
        if f.startswith("terminated-throughput-sim-" + app)
    ]

    sim_matches = {}

    for f in sim_files:
        (app, m, c, p, e, a) = parse_params(f, app)

        if (m == nodes and c == cores and e == events and a == arrival):
            sim_matches[p] = f

    # -----------------------------
    # Use only the INTERSECTION of parallelisms
    # -----------------------------
    real_parallelisms = set(real_matches.keys())
    sim_parallelisms  = set(sim_matches.keys())

    common_parallelisms = sorted(real_parallelisms & sim_parallelisms)

    if not common_parallelisms:
        print("There are no common levels of parallelism between REAL and SIMULATED.")
        sys.exit(1)

    #print("ℹNiveles de paralelismo usados:", common_parallelisms)


    # -----------------------------
    # Calculate average throughput
    # -----------------------------
    real_avg = []
    sim_avg  = []
    parallelism_levels = common_parallelisms

    for p in parallelism_levels:
        real_file = os.path.join(REAL_DIR, real_matches[p])
        sim_file  = os.path.join(SIM_DIR,   sim_matches[p])

        real_tp = load_data(real_file)
        sim_tp  = load_data(sim_file)

        real_avg.append(np.mean(real_tp))
        sim_avg.append(np.mean(sim_tp))

    # -----------------------------
    # Plot
    # -----------------------------
    plt.figure()
    plt.plot(parallelism_levels, real_avg, marker='o', color='blue', label="Real")
    plt.plot(parallelism_levels, sim_avg, marker='o', color='red', label="Simulated")

    plt.title(
        f"Throughput - {app} \n"
        f"{nodes} nodes, {cores} cores, reqs={events}, rate={arrival}"
    )
    plt.xlabel("Parallelism operator level")
    plt.ylabel("Throughput")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    
    # ----------------------------------------------------------
    # Export plot to PNG file
    # ----------------------------------------------------------
    out_dir  = os.path.join(BASE_DIR, "plot-real-sim/terminated")
    out_name = f"terminated-throughput-real-sim-{app}-{str(nodes)}-{str(cores)}-{str(events)}-{str(arrival)}"
    out_path = os.path.join(out_dir, out_name)
    
    plt.savefig(f"{out_path}.pdf")
    plt.savefig(f"{out_path}.png")

    plt.show()

if __name__ == "__main__":
    main()
