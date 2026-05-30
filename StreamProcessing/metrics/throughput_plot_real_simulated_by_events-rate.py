import os
import sys
import numpy as np
import matplotlib.pyplot as plt


BASE_DIR = "metrics/nexmark/throughput"
REAL_DIR = os.path.join(BASE_DIR, "real")
SIM_DIR  = os.path.join(BASE_DIR, "simulated")

# ---------------------------------------------------------
# Utilities
# ---------------------------------------------------------

def load_data(filepath):
    """Load columns finish time and throughput."""
    ft, tp = [], []
    with open(filepath, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) != 2:
                continue
            ft.append(float(parts[0]))
            tp.append(float(parts[1]))
    return ft, tp


def parse_identifier_event_rate(identifier):
    """
    Starting from an identifier of type:
        '1-32-3-100000-5000'
    return:
        (eventos, tasa)
    """
    parts = list(map(int, identifier.split('-')))
    eventos = parts[3]
    tasa = parts[4]
    return eventos, tasa


def parse_identifier(filename, app):
    """
    Extract the primary identifier by removing 'q2-throughput-' and '.txt'
    F.g:
        q2-throughput-1-32-3-100000-5000.txt
    return:
        1-32-3-100000-5000
    """
    base = filename.replace(".txt", "").replace("throughput-", "")
    return base[len(app) + 1:]  # +1 por guion tras 'q2'


def scenario_key_evt_rate(identifier):
    """Order by ascending rate, then ascending eventse."""
    eventos, tasa = parse_identifier_event_rate(identifier)
    return (tasa, eventos)

def sci_not(n):
    """Convert an integer to short scientific notation (e.g., 100000 -> 1e5)."""
    return f"{n:.0e}".replace("+0", "").replace("+", "").replace("e0", "e")


# ---------------------------------------------------------
# SCRIPT PRINCIPAL
# ---------------------------------------------------------

def main():
    if len(sys.argv) < 5:
        print("Use:")
        print("  python throughput_plot_real_simulated_by_events-rate.py <app> <nodes> <cores> <parallelism>")
        print("Example:")
        print("  python throughput_plot_real_simulated_by_events-rate.py q2 1 32 3")
        return

    app   = sys.argv[1]
    nodes = sys.argv[2]
    cores = sys.argv[3]
    par   = sys.argv[4]

    #print("\nBuscando escenarios que coinciden con:")
    #print(f"  app={app}, nodes={nodes}, cores={cores}, parallelism={par}\n")

    # -----------------------------------------------------
    # Filter files
    # -----------------------------------------------------
    real_files = [f for f in os.listdir(REAL_DIR) if f.startswith(app)]
    sim_files  = [f for f in os.listdir(SIM_DIR)  if f.startswith(app)]

    # Identifiers
    real_ids = {}
    sim_ids  = {}

    # Find exact matches of:
    # nodes-cores-par-*-*
    prefix = f"{nodes}-{cores}-{par}-"

    for f in real_files:
        ident = parse_identifier(f, app)
        if ident.startswith(prefix):
            real_ids[ident] = f

    for f in sim_files:
        ident = parse_identifier(f, app)
        if ident.startswith(prefix):
            sim_ids[ident] = f

    # -----------------------------------------------------
    # Intersection of EVENTS-RATE
    # -----------------------------------------------------
    common_ids = sorted(set(real_ids.keys()) & set(sim_ids.keys()), key=scenario_key_evt_rate)

    if not common_ids:
        print("There are no common real/simulated scenarios for this configuration.")
        return

    #print("Scenarios found (event-rate):")
    #for cid in common_ids:
    #    e, t = parse_identifier_event_rate(cid)
    #    print(f"  {e}-{t}")
    #print()

    # -----------------------------------------------------
    # Calculating averages
    # -----------------------------------------------------
    x_labels      = []
    real_ft_means = []
    sim_ft_means  = []
    real_tp_means = []
    sim_tp_means  = []

    for ident in common_ids:
        eventos, tasa = parse_identifier_event_rate(ident)

        real_file = os.path.join(REAL_DIR, real_ids[ident])
        sim_file  = os.path.join(SIM_DIR,  sim_ids[ident])

        real_ft, real_tp = load_data(real_file)
        sim_ft,  sim_tp  = load_data(sim_file)

        mean_real_ft = np.mean(real_ft)
        mean_sim_ft  = np.mean(sim_ft)

        mean_real_tp = np.mean(real_tp)
        mean_sim_tp  = np.mean(sim_tp)

        # Guardar valores para graficar
        x_labels.append(f"{sci_not(eventos)} - {sci_not(tasa)}")
        real_ft_means.append(mean_real_ft)
        sim_ft_means.append(mean_sim_ft)
        real_tp_means.append(mean_real_tp)
        sim_tp_means.append(mean_sim_tp)

    # -----------------------------------------------------
    # NORMALIZE THROUGHPUT: accuracy relative to the actual
    # -----------------------------------------------------
    tp_sim_norm = [
        max(0, (1 - abs(sim_tp_means[i] - real_tp_means[i]) / real_tp_means[i]) * 100)
        for i in range(len(x_labels))
    ]

    # -----------------------------------------------------
    # SINGLE GRAPH: simulated throughput accuracy
    # -----------------------------------------------------
    plt.figure(figsize=(10, 6))
    plt.plot(x_labels, tp_sim_norm, marker="o", label="Simulated accuracy")

    # Labels directly on each point
    for i, val in enumerate(tp_sim_norm):
        plt.text(
            i, val + 1,                     # position (above the point)
            f"{val:.1f}%",                  # text
            ha="center", va="bottom",
            fontsize=9
        )

    plt.title(
        f"Throughput Accuracy - {app} ({nodes} nodes, {cores} cores, parallelism={par})"
    )
    plt.xlabel("Events - Rate")
    plt.ylabel("Accuracy (%)")
    plt.ylim(0, 110)  # Leave some space at the top for the labels
    plt.grid(True)
    #plt.xticks(rotation=45)
    plt.tight_layout()
    
    # ----------------------------------------------------------
    # Export plot to PNG file
    # ----------------------------------------------------------
    out_dir  = os.path.join(BASE_DIR, "graphics-real-sim")
    out_name = f"throughput-real-sim-{app}-{str(nodes)}-{str(cores)}-{str(par)}.png"
    out_path = os.path.join(out_dir, out_name)
    plt.savefig(out_path, dpi=300, bbox_inches='tight')
    plt.show()


if __name__ == "__main__":
    main()
