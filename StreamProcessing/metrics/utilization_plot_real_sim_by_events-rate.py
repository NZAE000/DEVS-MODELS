import os
import sys
import matplotlib.pyplot as plt

# Paths
BASE_DIR = "metrics/nexmark/utilization"
REAL_DIR = os.path.join(BASE_DIR, "real/terminated")
SIM_DIR  = os.path.join(BASE_DIR, "sim/terminated")

# -------------------- Load Utilization File --------------------
def load_util_file(path):
    """
    Read lines:   op1:val1;op2:val2;...
    Returns a list of dicts: [{op: val, ...}, ...]
    """
    results = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entries = line.split(";")
            d = {}
            for e in entries:
                if ":" not in e:
                    continue
                op, val = e.split(":")
                d[op] = float(val)
            results.append(d)
    return results


# -------------------- Parse Scenario Identifier --------------------
def parse_identifier(filename, app):
    """
    File name:
        terminated-utilization-sim-q3-1-32-1-100000-5000.txt or terminated-utilization-real-q3-1-32-1-100000-5000.txt 
        q<app>-utilization-nodes-cores-par-events-arrival.txt

    Return tuple:
        (nodes, cores, par, events, arrival)
    """
    base = filename.replace(".txt", "").replace(f"terminated-utilization-sim-{app}-", "").replace(f"terminated-utilization-real-{app}-", "")
    parts = base.split("-")
    if len(parts) != 5:
        raise ValueError(f"Invalid name: {filename}")
    nodes, cores, par, events, arrival = parts
    return int(nodes), int(cores), int(par), int(events), int(arrival)


# -------------------- Main --------------------
def main():
    if len(sys.argv) != 5:
        print("Use:")
        print(" python utilization_by_events_rate.py <app> <nodes> <cores> <parallelism>")
        return

    app   = sys.argv[1]
    nodes = int(sys.argv[2])
    cores = int(sys.argv[3])
    par   = int(sys.argv[4])

    # ---------------------------------------------------------
    # Search files for specific cfg
    # ---------------------------------------------------------
    real_files = []
    sim_files  = []

    for fname in os.listdir(REAL_DIR):
        if fname.startswith(f"terminated-utilization-real-{app}"):
            print("aca")
            try:
                n, c, p, ev, ar = parse_identifier(fname, app)
                if n == nodes and c == cores and p == par:
                    real_files.append((ev, ar, fname))
            except:
                continue

    for fname in os.listdir(SIM_DIR):
        if fname.startswith(f"terminated-utilization-sim-{app}"):
            try:
                n, c, p, ev, ar = parse_identifier(fname, app)
                if n == nodes and c == cores and p == par:
                    sim_files.append((ev, ar, fname))
            except:
                continue

    if not real_files:
        print("No REAL files were found for that configuration.")
        return
    if not sim_files:
        print("No SIMULATED files were found for that configuration..")
        return

    # Convert to dict by scenary (events, arrival)
    real_dict = {(ev, ar): fn for (ev, ar, fn) in real_files}
    sim_dict  = {(ev, ar): fn for (ev, ar, fn) in sim_files}

    # ---------------------------------------------------------
    # Verify match scenary
    # ---------------------------------------------------------
    real_scen = set(real_dict.keys())
    sim_scen  = set(sim_dict.keys())

    if real_scen != sim_scen:
        missing_in_sim  = real_scen - sim_scen
        missing_in_real = sim_scen - real_scen

        if missing_in_sim:
            print("ERROR: scenarios are missing in SIMULATED:", missing_in_sim)
        if missing_in_real:
            print("ERROR: scenarios are missing in REAL:", missing_in_real)
        return

    # Order scenaries by arrival rate (smallest to largest)
    scenarios = sorted(real_scen, key=lambda x: x[1])

    # ---------------------------------------------------------
    # Process files: validate operators and get avg
    # ---------------------------------------------------------
    avg_real = {}
    avg_sim  = {}
    operators = None

    for (ev, ar) in scenarios:

        # ---- Load files ----
        real_path = os.path.join(REAL_DIR, real_dict[(ev, ar)])
        sim_path  = os.path.join(SIM_DIR,  sim_dict[(ev, ar)])

        real_runs = load_util_file(real_path)
        sim_runs  = load_util_file(sim_path)

        # ---- Verify same set of operators ----
        real_ops = set(real_runs[0].keys())
        sim_ops  = set(sim_runs[0].keys())

        if real_ops != sim_ops:
            print("ERROR: The operators do not match in the scenario events={}, arrival={}".format(ev, ar))
            print("  Missing from SIM:", real_ops - sim_ops)
            print("  Missing from REAL:", sim_ops - real_ops)
            return

        if operators is None:
            operators = sorted(real_ops)

        # ---- Average utilization per operator ----
        r_avg = {op: sum(run[op] for run in real_runs)/len(real_runs) for op in operators}
        s_avg = {op: sum(run[op] for run in sim_runs)/len(sim_runs) for op in operators}

        avg_real[(ev, ar)] = r_avg
        avg_sim[(ev, ar)]  = s_avg

    # ---------------------------------------------------------
    # Building series for graphing
    # ---------------------------------------------------------
    x_labels = [f"{ev}\n{ar}" for (ev, ar) in scenarios]
    x_pos    = list(range(len(scenarios)))

    op_real_series = {op: [] for op in operators}
    op_sim_series  = {op: [] for op in operators}

    for scen in scenarios:
        for op in operators:
            op_real_series[op].append(avg_real[scen][op])
            op_sim_series[op].append(avg_sim[scen][op])

    # ---------------------------------------------------------
    # Plot
    # ---------------------------------------------------------
    plt.figure(figsize=(10, 6))
    cmap = plt.get_cmap("tab20")
    base_colors = [cmap(i % cmap.N) for i in range(len(operators))]
    
    # To store legend handlers
    real_handles = []
    sim_handles  = []

    for i, op in enumerate(operators):
        color = base_colors[i]

        # Real: darkest
        real_line, = plt.plot(x_pos, op_real_series[op],
                 label=f"{op}",
                 color=color,
                 linewidth=2.3,
                 marker="o")
        real_handles.append(real_line)

        # Simulated: lightest
        light = (color[0], color[1], color[2], 0.45)
        sim_line, = plt.plot(x_pos, op_sim_series[op],
                 label=f"{op}",
                 color=light,
                 linewidth=1.8,
                 linestyle="--",
                 marker="s")
        sim_handles.append(sim_line)

    plt.title(
        f"Operator utilization - {app} ({nodes} nodes, {cores} cores, parallelism={par})"
    )
    plt.xlabel("Events — Arrival Rate")
    plt.ylabel("Utilization")
    plt.xticks(x_pos, x_labels, rotation=25)
    plt.grid(True)
    
    
    # ---------------------------
    #   Legends side-by-side
    # ---------------------------

    ax = plt.gca()

    # SIMULATED legend (ONLY styles, NO names)
    legend_sim = ax.legend(
        handles=sim_handles,
        labels=[""] * len(sim_handles),   # Empty names
        title="Sim",
        loc="center left",
        bbox_to_anchor=(0.01, 0.55),
        frameon=True
    )
    ax.add_artist(legend_sim)
    
    # REAL Legend (operator names + solid lines)
    legend_real = ax.legend(
        handles=real_handles,
        title="Real",
        loc="center left",
        bbox_to_anchor=(0.065, 0.55),
        frameon=True
    )
    legend_real.get_title().set_position((-220,0))
    
    plt.tight_layout()

    # ----------------------------------------------------------
    # Export plot to PNG file
    # ----------------------------------------------------------
    out_dir  = os.path.join(BASE_DIR, "plot-real-sim/terminated")
    out_name = f"terminated-utilization-real-sim-{app}-{nodes}-{cores}-{par}.png"
    out_path = os.path.join(out_dir, out_name)
    plt.savefig(out_path, dpi=300, bbox_inches='tight')
    
    plt.show()

if __name__ == "__main__":
    main()
