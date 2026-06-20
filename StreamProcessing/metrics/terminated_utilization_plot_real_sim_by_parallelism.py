#!/usr/bin/env python3
import os
import sys
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from collections import defaultdict, OrderedDict

plt.style.use("metrics/thesis.mplstyle")

# Paths
BASE_DIR = "metrics/nexmark/utilization"
REAL_DIR = os.path.join(BASE_DIR, "real/terminated")
SIM_DIR  = os.path.join(BASE_DIR, "sim/terminated")

def read_util_file(path):
    """
    Read a utilization file with lines of the type:
      operA:0.123;operB:0.456;...;
    Return: dict operador -> list of values ​​(one list per line)
    """
    op_values = defaultdict(list)
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            pairs = [p for p in line.split(';') if p]
            for pair in pairs:
                if ':' not in pair:
                    continue
                name, val = pair.split(':', 1)
                try:
                    v = float(val)
                except:
                    # ignorar valores no-numéricos
                    continue
                op_values[name].append(v)
    return op_values  # operador -> [v1, v2, ...]

def mean_per_operator(op_values):
    """
    op_values: dict operator -> [v1, v2, ...]
    return dict operator -> mean(v)
    """
    return {op: float(np.mean(vals)) if vals else 0.0 for op, vals in op_values.items()}

def parse_identifier_from_filename(filename, appname):
    """
    Extract the identifier after 'qX-<prefix_word>-' and without '.txt'
    f.g:
           terminated-utilization-real-q3-1-32-1-100000-5000.txt
        or terminated-utilization-sim-q3-1-32-1-100000-5000.txt
    => '1-32-1-100000-5000'
    """
    base = filename.replace(".txt", "")
    base = base.replace("terminated-utilization-real-", "").replace("terminated-utilization-sim-", "")
    
    # Now remove leading "qN-"
    if base.startswith(appname + "-"):
        ident = base[len(appname)+1:]
    else:
        # fallback: try split by first hyphen
        parts = base.split('-', 1)
        ident = parts[1] if len(parts) > 1 else base
    return ident

def scenario_key(identifier):
    # identifier form: nodes-cores-par-events-rate (all numeric)
    parts = identifier.split('-')
    try:
        a,b,c,d,e = map(int, parts)
        return (int(c), int(d), int(e), int(a), int(b))  # pero we'll sort by paral (c) asc
    except:
        # fallback lexicográfico
        return tuple(parts)

def main():
    if len(sys.argv) < 6:
        print("Use: python utilization_plot_real_sim_by_parallelism.py <app> <nodes> <cores> <events> <arrival>")
        print("f.g: python utilization_plot_real_simu_by_parallelism.py q3 1 32 100000 5000")
        return

    app     = sys.argv[1]
    nodes   = sys.argv[2]
    cores   = sys.argv[3]
    events  = sys.argv[4]
    arrival = sys.argv[5]

    #print(f"\nComparando utilization real vs sim para:")
    #print(f" app={app}, nodes={nodes}, cores={cores}, events={events}, arrival={arrival}\n")

    # List files
    real_files = [f for f in os.listdir(REAL_DIR) if f.startswith("terminated-utilization-real-" + app)]
    sim_files  = [f for f in os.listdir(SIM_DIR)  if f.startswith("terminated-utilization-sim-" + app)]

    # Filter by prefix nodes-cores-par-... -> we want different paral levels
    prefix = f"{nodes}-{cores}-"
    real_map = {}   # ident -> filename
    sim_map  = {}

    for f in real_files:
        ident = parse_identifier_from_filename(f, app)
        if ident.startswith(prefix) and ident.endswith(f"{events}-{arrival}"):
            # pattern: nodes-cores-par-events-arrival -> we keep par varying
            real_map[ident] = f

    for f in sim_files:
        ident = parse_identifier_from_filename(f, app)
        if ident.startswith(prefix) and ident.endswith(f"{events}-{arrival}"):
            sim_map[ident] = f

    if not real_map:
        print("No REAL files were found for that configuration.")
        return
    if not sim_map:
        print("No SIMULATED files were found for that configuration..")
        return

    # Check parallelism levels presence in both sides
    real_pars = sorted(list(real_map.keys()), key=lambda x: int(x.split('-')[2]))
    sim_pars  = sorted(list(sim_map.keys()),  key=lambda x: int(x.split('-')[2]))

    real_set = set(real_map.keys())
    sim_set  = set(sim_map.keys())

    missing_in_sim = sorted(list(real_set - sim_set), key=lambda x: int(x.split('-')[2]))
    missing_in_real = sorted(list(sim_set - real_set), key=lambda x: int(x.split('-')[2]))

    if missing_in_sim:
        print("ERROR: SIMULATED lacks parallelism levels for this configuration:")
        for m in missing_in_sim:
            print("  -", m)
        print("Terminated.")
        sys.exit(1)

    if missing_in_real:
        print("ERROR: There are no REAL parallelism levels for this configuration:")
        for m in missing_in_real:
            print("  -", m)
        print("Terminated.")
        sys.exit(1)

    # Use sorted parallelism levels (by integer value of 'par')
    common_ids = sorted(real_set & sim_set, key=lambda x: int(x.split('-')[2]))
    paral_levels = [int(x.split('-')[2]) for x in common_ids]

    #print("Niveles de paralelismo encontrados:", paral_levels)
    #print()

    # For each ident (parallelism level) compute mean per operator from file
    # and also capture operator sets
    real_stats = OrderedDict()  # ident -> {op:mean}
    sim_stats  = OrderedDict()
    operator_set = None

    for ident in common_ids:
        real_path = os.path.join(REAL_DIR, real_map[ident])
        sim_path  = os.path.join(SIM_DIR,  sim_map[ident])

        # Read and compute per-file means
        real_ops_vals = read_util_file(real_path)
        sim_ops_vals  = read_util_file(sim_path)

        real_means = mean_per_operator(real_ops_vals)
        sim_means  = mean_per_operator(sim_ops_vals)

        # Pperator name sets for this ident
        real_ops = set(real_means.keys())
        sim_ops  = set(sim_means.keys())

        if real_ops != sim_ops:
            missing_ops_in_sim = sorted(list(real_ops - sim_ops))
            missing_ops_in_real = sorted(list(sim_ops - real_ops))
            if missing_ops_in_sim:
                print(f"ERROR: For scenario {ident}, operators are missing in SIM:")
                for op in missing_ops_in_sim:
                    print("   -", op)
            if missing_ops_in_real:
                print(f"ERROR: For scenario {ident}, operators are missing in REAL:")
                for op in missing_ops_in_real:
                    print("   -", op)
            print("Terminated due to missing operators.")
            sys.exit(1)

        # Initialize operator_set from first ident, and check it remains the same across idents
        if operator_set is None:
            operator_set = set(real_means.keys())
        else:
            if set(real_means.keys()) != operator_set:
                # find where it differs
                diff1 = operator_set - set(real_means.keys())
                diff2 = set(real_means.keys()) - operator_set
                print(f"ERROR: The operator set changed in {ident}.")
                if diff1:
                    print("  Missing operators (previously present):", diff1)
                if diff2:
                    print("  New operators appeared:", diff2)
                print("Terminated.")
                sys.exit(1)

        real_stats[ident] = real_means
        sim_stats[ident]  = sim_means

    # At this point operator_set exists and is same for all idents
    operators = sorted(operator_set)  # sorted names for consistent colors/order
    #print("Operadores detectados (ordenados):")
    #for op in operators:
    #    print("  -", op)
    #print()

    # Build data for plotting: for each operator, a list of values across paral_levels
    op_real_series = {op: [] for op in operators}
    op_sim_series  = {op: [] for op in operators}

    for ident in common_ids:
        for op in operators:
            op_real_series[op].append(real_stats[ident][op])
            op_sim_series[op].append(sim_stats[ident][op])

    # ---------------------------------------------------------
    # Plot
    # ---------------------------------------------------------
    plt.figure()
    cmap  = plt.get_cmap("tab20")
    n_ops = len(operators)
    base_colors = [cmap(i % cmap.N) for i in range(n_ops)]
    
    # To store legend handlers
    #real_handles = []
    #sim_handles  = []

    for i, op in enumerate(operators):
        color = base_colors[i]

        # --- REAL (strong color) ---
        real_line, = plt.plot(
            paral_levels, op_real_series[op],
            label=f"{op}",
            color=color,
            marker='o'
        )
        #real_handles.append(real_line)

        # --- SIMULATED (soft color + dashed) ---
        light_color = (color[0], color[1], color[2], 0.45)
        sim_line, = plt.plot(
            paral_levels, op_sim_series[op],
            label=f"{op}",
            color=light_color,
            linestyle='--',
            marker='o'
        )
        #sim_handles.append(sim_line)


    plt.title(
        f"Operator utilization - {app}\n"
        f"{nodes} nodes, {cores} cores, reqs={events}, rate={arrival}"
    )
    plt.xlabel("Parallelism level")
    plt.ylabel("Utilization")
    plt.xticks(paral_levels)
    plt.grid(True)

    # ---------------------------
    #   Legends
    # ---------------------------
    ax = plt.gca()

    # ---------------------------
    # Main leyend (operators)
    # ---------------------------
    operator_handles = []
    for i, op in enumerate(operators):

        color = base_colors[i]

        operator_handles.append(
            Line2D(
                [0],
                [0],
                marker='s',
                linestyle='None',
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

    ax.add_artist(legend_ops)

    # ---------------------------
    # Secundary (styles)
    # ---------------------------
    style_handles = [
        Line2D(
            [0], [0],
            color="black",
            linestyle="-",
            linewidth=2,
            label="Real"
        ),
        Line2D(
            [0], [0],
            color="black",
            linestyle="--",
            linewidth=2,
            label="Simulated"
        )
    ]

    legend_style = ax.legend(
        handles=style_handles,
        loc="upper right",
        frameon=True
    )

    plt.subplots_adjust(bottom=0.3)
    
    # ----------------------------------------------------------
    # Export plot to PNG file
    # ----------------------------------------------------------
    out_dir = os.path.join(BASE_DIR, "plot-real-sim/terminated")
    out_name = f"terminated-utilization-real-sim-{app}-{nodes}-{cores}-{events}-{arrival}"
    out_path = os.path.join(out_dir, out_name)
    
    plt.savefig(f"{out_path}.pdf", bbox_extra_artists=(legend_ops,))
    plt.savefig(f"{out_path}.png", bbox_extra_artists=(legend_ops,))
    
    plt.show()


if __name__ == "__main__":
    main()
