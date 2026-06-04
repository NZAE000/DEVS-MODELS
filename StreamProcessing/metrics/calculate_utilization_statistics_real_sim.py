import os
import sys
import numpy as np
import random
import csv

# Paths
BASE_DIR = "metrics/nexmark/utilization"
REAL_DIR = os.path.join(BASE_DIR, "real/terminated")
SIM_DIR  = os.path.join(BASE_DIR, "simulated/terminated")

# -------------------------
# LOAD
# -------------------------
def load_utilization(filepath):
    data = {}

    with open(filepath, "r") as f:
        for line in f:
            parts = line.strip().split(";")
            for p in parts:
                if ":" not in p:
                    continue
                op, val = p.split(":")
                if val == "":
                    continue

                val = float(val)

                if op not in data:
                    data[op] = []

                data[op].append(val)

    return data


# -------------------------
# PAD
# -------------------------
def pad_data(short_list, long_len):
    if len(short_list) == long_len:
        return short_list.copy()

    padded = short_list.copy()
    while len(padded) < long_len:
        a, b = random.sample(short_list, 2)
        padded.append(np.median([a, b]))

    return padded


# -------------------------
# METRICS
# -------------------------
def compute_rmse(r, s):
    return np.sqrt(np.mean((np.array(r) - np.array(s)) ** 2))


def compute_accuracy(real, sim):
    if real == 0.0:
        return 0.0
    acc = 1 - abs(real - sim) / real
    #print("r:", real, "sim:", sim)
    #print("abs", abs(real - sim))
    #print("err", abs(real - sim) / real)
    return max(0.0, min(acc, 1.0))

def compute_pearson(x, y):
    if len(x) < 2:
        return 0.0
    return np.corrcoef(x, y)[0, 1]

def compute_spearman(x, y):
    if len(x) < 2:
        return 0.0

    # ranking manual (sin scipy)
    rank_x = np.argsort(np.argsort(x))
    rank_y = np.argsort(np.argsort(y))

    return np.corrcoef(rank_x, rank_y)[0, 1]

# -------------------------
# PARSE
# -------------------------
def parse_identifier(filename, appname):
    base = filename.replace(".txt", "").replace("terminated-utilization-sim-", "").replace("terminated-utilization-real-", "")
    return base[len(appname) + 1:]


def scenario_key(identifier):
    comp, cores, par, events, arrival = map(int, identifier.split('-'))
    return (arrival, events, comp, cores, par)


# -------------------------
# MAIN
# -------------------------
def main():
    if len(sys.argv) < 2:
        print("Use: python3 calculate_utilization_statistics_real_sim.py <app>")
        return

    appname = sys.argv[1]

    real_files = [f for f in os.listdir(REAL_DIR) if f.startswith("terminated-utilization-real-" + appname)]
    sim_files  = [f for f in os.listdir(SIM_DIR) if f.startswith("terminated-utilization-sim-" + appname)]

    real_ids = {parse_identifier(f, appname): f for f in real_files}
    sim_ids  = {parse_identifier(f, appname): f for f in sim_files}

    common_ids = sorted(real_ids.keys() & sim_ids.keys(), key=scenario_key)

    # estructura: scenario → operator → stats
    stats = {}
    errors = {}
    all_ops = set()

    for identifier in common_ids:
        real_file = os.path.join(REAL_DIR, real_ids[identifier])
        sim_file  = os.path.join(SIM_DIR, sim_ids[identifier])

        real_data = load_utilization(real_file)
        sim_data  = load_utilization(sim_file)

        operators = sorted(set(real_data.keys()) & set(sim_data.keys()))
        all_ops.update(operators)

        stats[identifier] = {}
        errors[identifier] = {}

        for op in operators:
            r = real_data[op]
            s = sim_data[op]

            max_len = max(len(r), len(s))
            r_p = pad_data(r, max_len)
            s_p = pad_data(s, max_len)

            stats[identifier][op] = {
                "sim_mean": np.mean(s),
                "sim_std": np.std(s),
                "real_mean": np.mean(r),
                "real_std": np.std(r)
            }

            errors[identifier][op] = {
                "rmse": compute_rmse(r_p, s_p),
                "acc": compute_accuracy(np.mean(r), np.mean(s))
            }
            
            #print("opr:", op, "mean r:", np.mean(r), "mean s:", np.mean(s), "acc:", compute_accuracy(np.mean(r), np.mean(s)))

    all_ops = sorted(all_ops)
    
    # -------------------------
    # PEARSON DATA COLLECTION
    # -------------------------
    
    # Por operador → listas agregadas
    pearson_rate = {op: {"real": [], "sim": []} for op in all_ops}
    pearson_par  = {op: {"real": [], "sim": []} for op in all_ops}

    # Agrupaciones
    group_by_par = {}   # P fix → variando rate
    group_by_rate = {}  # Rate fix → variando P

    for sc in common_ids:
        comp, cores, par, events, rate = sc.split('-')

        key_par = (comp, cores, par)            # fija P
        key_rate = (comp, cores, events, rate)  # fija carga

        if key_par not in group_by_par:
            group_by_par[key_par] = []
        group_by_par[key_par].append(sc)

        if key_rate not in group_by_rate:
            group_by_rate[key_rate] = []
        group_by_rate[key_rate].append(sc)


    # -------------------------
    # BUILD PEARSON ARRAYS
    # -------------------------

    # Dominio req-rate (P fix)
    for key, scenarios in group_by_par.items():
        scenarios_sorted = sorted(scenarios, key=lambda x: int(x.split('-')[4]))  # Order by rate

        for op in all_ops:
            real_vals = []
            sim_vals = []

            for sc in scenarios_sorted:
                if op in stats[sc]:
                    real_vals.append(stats[sc][op]["real_mean"])
                    sim_vals.append(stats[sc][op]["sim_mean"])

            if len(real_vals) > 1:
                pearson_rate[op]["real"].extend(real_vals)
                pearson_rate[op]["sim"].extend(sim_vals)


    # Dominio P (load fix)
    for key, scenarios in group_by_rate.items():
        scenarios_sorted = sorted(scenarios, key=lambda x: int(x.split('-')[2]))  # Order by P

        for op in all_ops:
            real_vals = []
            sim_vals = []

            for sc in scenarios_sorted:
                if op in stats[sc]:
                    real_vals.append(stats[sc][op]["real_mean"])
                    sim_vals.append(stats[sc][op]["sim_mean"])

            if len(real_vals) > 1:
                pearson_par[op]["real"].extend(real_vals)
                pearson_par[op]["sim"].extend(sim_vals)

    # -------------------------
    # PRINT TABLE 1
    # -------------------------
    print("\n=========== UTILIZATION (MEAN & STD) ===========\n")

    header = "hw     repl  events   rate   | "
    for op in all_ops:
        header += f"{op:^32}|"
    print(header)

    subheader = " " * 32 + "| "
    for _ in all_ops:
        subheader += "S_m      S_std    R_m      R_std  |"
    print(subheader)

    print("-" * len(header))

    for sc in common_ids:
        comp, cores, repl, events, rate = sc.split('-')
        hw = f"{comp}-{cores}"

        row = f"{hw:<6} {repl:<5} {events:<8} {rate:<7} | "

        for op in all_ops:
            if op in stats[sc]:
                d = stats[sc][op]
                row += f"{d['sim_mean']:.4f} {d['sim_std']:.4f} {d['real_mean']:.4f} {d['real_std']:.4f} |"
            else:
                row += " -       -       -       -      |"

        print(row)

    # -------------------------
    # PRINT TABLE 2
    # -------------------------
    print("\n=========== RMSE & ACCURACY ===========\n")

    header = "hw     repl  events   rate   | "
    for op in all_ops:
        header += f"{op:^24}|"
    print(header)

    subheader = " " * 32 + "| "
    for _ in all_ops:
        subheader += "RMSE       ACC      |"
    print(subheader)

    print("-" * len(header))

    for sc in common_ids:
        comp, cores, repl, events, rate = sc.split('-')
        hw = f"{comp}-{cores}"

        row = f"{hw:<6} {repl:<5} {events:<8} {rate:<7} | "

        for op in all_ops:
            if op in errors[sc]:
                e = errors[sc][op]
                row += f"{e['rmse']:.6f} {e['acc']:.6f} |"
            else:
                row += " -         -       |"

        print(row)
        
    # -------------------------
    # PRINT TABLE 3 (PEARSON RATE)
    # -------------------------
    print("\n=========== PEARSON (REQ-RATE DOMAIN) ===========\n")

    header = ""
    for op in all_ops:
        header += f"{op:^15}|"
    print(header)
    print("-" * len(header))

    row = ""
    for op in all_ops:
        r = pearson_rate[op]["real"]
        s = pearson_rate[op]["sim"]

        val = compute_pearson(r, s) if len(r) > 1 else 0.0
        row += f"{val:^15.6f}|"

    print(row)


    # -------------------------
    # PRINT TABLE 4 (SPEARMAN PARALLELISM)
    # -------------------------
    print("\n=========== SPEARMAN (PARALLELISM DOMAIN) ===========\n")

    header = ""
    for op in all_ops:
        header += f"{op:^15}|"
    print(header)
    print("-" * len(header))

    row = ""
    for op in all_ops:
        r = pearson_par[op]["real"]
        s = pearson_par[op]["sim"]

        val = compute_spearman(r, s) if len(r) > 1 else 0.0
        row += f"{val:^15.6f}|"

    print(row)

    # -------------------------
    # CSV
    # -------------------------
    csv_dir  = os.path.join(BASE_DIR, "statistics-real-sim/terminated")
    csv_name = f"terminated-utilization-real-sim-statics-{appname}.csv"
    csv_path = os.path.join(csv_dir, csv_name)

    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f, delimiter=';')

        # HEADER TABLE 1
        header = ["hw", "repl", "events", "rate"]
        for op in all_ops:
            header += [f"{op}_S_m", f"{op}_S_std", f"{op}_R_m", f"{op}_R_std"]
        writer.writerow(header)

        for sc in common_ids:
            comp, cores, repl, events, rate = sc.split('-')
            hw = f"{comp}-{cores}"

            row = [hw, repl, events, rate]

            for op in all_ops:
                if op in stats[sc]:
                    d = stats[sc][op]
                    row += [
                        f"{d['sim_mean']:.6f}",
                        f"{d['sim_std']:.6f}",
                        f"{d['real_mean']:.6f}",
                        f"{d['real_std']:.6f}"
                    ]
                else:
                    row += ["", "", "", ""]

            writer.writerow(row)

        writer.writerow([])

        # HEADER TABLE 2
        header = ["hw", "repl", "events", "rate"]
        for op in all_ops:
            header += [f"{op}_RMSE", f"{op}_ACC"]
        writer.writerow(header)

        for sc in common_ids:
            comp, cores, repl, events, rate = sc.split('-')
            hw = f"{comp}-{cores}"

            row = [hw, repl, events, rate]

            for op in all_ops:
                if op in errors[sc]:
                    e = errors[sc][op]
                    row += [
                        f"{e['rmse']:.6f}",
                        f"{e['acc']:.6f}"
                    ]
                else:
                    row += ["", ""]

            writer.writerow(row)
        
        writer.writerow([])

        # -------------------------
        # TABLE 3: PEARSON RATE
        # -------------------------
        header = []
        for op in all_ops:
            header.append(f"{op}_pearson_rate")
        writer.writerow(header)

        row = []
        for op in all_ops:
            r = pearson_rate[op]["real"]
            s = pearson_rate[op]["sim"]

            val = compute_pearson(r, s) if len(r) > 1 else 0.0
            row.append(f"{val:.6f}")

        writer.writerow(row)

        writer.writerow([])

        # -------------------------
        # TABLE 4: SPEARMAN PARALLELISM
        # -------------------------
        header = []
        for op in all_ops:
            header.append(f"{op}_pearson_par")
        writer.writerow(header)

        row = []
        for op in all_ops:
            r = pearson_par[op]["real"]
            s = pearson_par[op]["sim"]

            val = compute_spearman(r, s) if len(r) > 1 else 0.0
            row.append(f"{val:.6f}")

        writer.writerow(row)

    print(f"\nCSV generado: {csv_path}\n")


if __name__ == "__main__":
    main()