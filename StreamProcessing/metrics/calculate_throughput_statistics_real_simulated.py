import os
import sys
import numpy as np
import random
import csv

REAL_PATH = "metrics/nexmark/throughput/real"
SIM_PATH  = "metrics/nexmark/throughput/simulated"


def load_data(filepath):
    ft, tp = [], []
    with open(filepath, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) != 2:
                continue
            a, b = float(parts[0]), float(parts[1])
            ft.append(a)
            tp.append(b)
    return ft, tp


def pad_data(short_list, long_len):
    if len(short_list) == long_len:
        return short_list.copy()

    padded = short_list.copy()
    while len(padded) < long_len:
        a, b = random.sample(short_list, 2)
        padded.append(np.median([a, b]))
    return padded


def compute_rmse(r, s):
    arr1 = np.array(r)
    arr2 = np.array(s)
    return np.sqrt(np.mean((arr1 - arr2) ** 2))


def compute_accuracy(real, sim):
    """
    Accuracy = 1 − |real − simulated| / real
    Y limitada a máximo 1.0 (100%)
    """
    real = float(real)
    sim  = float(sim)

    if real == 0:
        return 0.0

    acc = 1 - abs(real - sim) / real
    return max(0.0, min(acc, 1.0))  # clamp


def parse_identifier(filename, appname):
    base = filename.replace(".txt", "").replace("throughput-", "")
    return base[len(appname) + 1:]


def print_custom_table(results):
    W_ESC = 26
    W = 12

    # Tabla principal (sin RMSE)
    line1 = (
        f"{'':^{W_ESC}} | "
        f"{'Simulated':^{W*4}} | "
        f"{'Real':^{W*4}}"
    )

    line2 = (
        f"{'Scenario':^{W_ESC}} | "
        f"{'-'* (W*4)} | "
        f"{'-'* (W*4)}"
    )

    line3 = (
        f"{'':<{W_ESC}} | "
        f"{'Finishtime':^{W*2}}{'Throughput':^{W*2}} | "
        f"{'Finishtime':^{W*2}}{'Throughput':^{W*2}}"
    )

    line4 = (
        f"{'-'*W_ESC} | "
        f"{'-'*W}{'-'*W}{'-'*W}{'-'*W} | "
        f"{'-'*W}{'-'*W}{'-'*W}{'-'*W}"
    )

    line5 = (
        f"{' hw':<{4}}{' repl':<{4}}{' events':<{8}}{' rate':<{9}} | "
        f"{'mean':^{W}}{'std':^{W}}{'mean':^{W}}{'std':^{W}} | "
        f"{'mean':^{W}}{'std':^{W}}{'mean':^{W}}{'std':^{W}}"
    )

    separator = "-" * (W_ESC + 9 + W*8)

    print(line1)
    print(line2)
    print(line3)
    print(line4)
    print(line5)
    print(separator)

    for r in results:
        row = (
            f"{r[0]:<{6}}{r[1]:<{4}}{r[2]:<{8}}{r[3]:<{8}} | "
            f"{r[4]:^{W}}{r[5]:^{W}}{r[6]:^{W}}{r[7]:^{W}} | "
            f"{r[8]:^{W}}{r[9]:^{W}}{r[10]:^{W}}{r[11]:^{W}}"
        )
        print(row)

    print(separator)


def print_rmse_accuracy_table(rmse_table):
    print("\n\n======= RMSE & ACCURACY =======\n")

    W = 14

    header = (
        f"{'Scenario':<22} | "
        f"{'RMSE_FT':^{W}}{'RMSE_TP':^{W}} | "
        f"{'ACC_FT':^{W}}{'ACC_TP':^{W}}"
    )

    sep = "-" * (22 + 3 + W*4)

    print(header)
    print(sep)

    for row in rmse_table:
        print(
            f"{row[0]:<22} | "
            f"{row[1]:^{W}.6f}{row[2]:^{W}.6f} | "
            f"{row[3]:^{W}.6f}{row[4]:^{W}.6f}"
        )


def sci(x):
    try:
        return f"{float(x):.6e}".replace('.', ',')
    except:
        return x


def scenario_key(identifier):
    comp, cores, par, events, arrival = map(int, identifier.split('-'))
    return (arrival, events, comp, cores, par)


def main():
    if len(sys.argv) < 2:
        print("Use: python3 calculate_statistics_real_simulated.py <aplicacion>")
        return

    appname = sys.argv[1]

    real_files = [f for f in os.listdir(REAL_PATH) if f.startswith(appname)]
    sim_files  = [f for f in os.listdir(SIM_PATH) if f.startswith(appname)]

    real_ids = {parse_identifier(f, appname): f for f in real_files}
    sim_ids  = {parse_identifier(f, appname): f for f in sim_files}

    common_ids = sorted(real_ids.keys() & sim_ids.keys(), key=scenario_key)

    results = []
    rmse_accuracy_rows = []

    for identifier in common_ids:
        real_file = os.path.join(REAL_PATH, real_ids[identifier])
        sim_file  = os.path.join(SIM_PATH, sim_ids[identifier])

        real_ft, real_tp = load_data(real_file)
        sim_ft,  sim_tp  = load_data(sim_file)

        max_ft = max(len(real_ft), len(sim_ft))
        max_tp = max(len(real_tp), len(sim_tp))

        real_ft_p = pad_data(real_ft, max_ft)
        sim_ft_p  = pad_data(sim_ft,  max_ft)
        real_tp_p = pad_data(real_tp, max_tp)
        sim_tp_p  = pad_data(sim_tp,  max_tp)

        mean_real_ft = np.mean(real_ft)
        mean_sim_ft  = np.mean(sim_ft)
        std_real_ft  = np.std(real_ft)
        std_sim_ft   = np.std(sim_ft)

        mean_real_tp = np.mean(real_tp)
        mean_sim_tp  = np.mean(sim_tp)
        std_real_tp  = np.std(real_tp)
        std_sim_tp   = np.std(sim_tp)

        rmse_ft = compute_rmse(real_ft_p, sim_ft_p)
        rmse_tp = compute_rmse(real_tp_p, sim_tp_p)

        acc_ft = compute_accuracy(mean_real_ft, mean_sim_ft)
        acc_tp = compute_accuracy(mean_real_tp, mean_sim_tp)

        nodes, cores, replics, events, rate = identifier.split("-")
        hw = f"{nodes}-{cores}"

        results.append([
            hw, replics, events, rate,
            f"{mean_sim_ft:.6f}", f"{std_sim_ft:.6f}",
            f"{mean_sim_tp:.3f}", f"{std_sim_tp:.3f}",
            f"{mean_real_ft:.6f}", f"{std_real_ft:.6f}",
            f"{mean_real_tp:.3f}", f"{std_real_tp:.3f}"
        ])

        rmse_accuracy_rows.append([
            f"{hw}-{replics}-{events}-{rate}",
            rmse_ft, rmse_tp,
            acc_ft, acc_tp
        ])

    print_custom_table(results)
    print_rmse_accuracy_table(rmse_accuracy_rows)

    # -------------------------
    # CSV
    # -------------------------
    csv_filename = f"metrics/nexmark/throughput/throughput-statics-{appname}.csv"

    with open(csv_filename, "w", newline="") as csvfile:
        writer = csv.writer(csvfile, delimiter=';')

        # TABLA PRINCIPAL
        writer.writerow([
            "Scenario.hardware", "Scenario.replic",
            "Scenario.events", "Scenario.rate",
            "Simulated.FT.mean", "Simulated.FT.std",
            "Simulated.TP.mean", "Simulated.TP.std",
            "Real.FT.mean", "Real.FT.std",
            "Real.TP.mean", "Real.TP.std"
        ])

        for r in results:
            writer.writerow([
                r[0].replace('-', ';'),
                r[1],
                sci(r[2]),
                sci(r[3]),
                r[4].replace('.', ','), r[5].replace('.', ','),
                sci(r[6]), sci(r[7]),
                r[8].replace('.', ','), r[9].replace('.', ','),
                sci(r[10]), sci(r[11]),
            ])

        writer.writerow([])

        # TABLA RMSE + ACC
        writer.writerow([
            "Scenario",
            "RMSE.Finishtime", "RMSE.Throughput",
            "Accuracy.Finishtime", "Accuracy.Throughput"
        ])

        for row in rmse_accuracy_rows:
            writer.writerow([
                row[0],
                f"{row[1]:.6f}".replace('.', ','),
                sci(row[2]),
                f"{row[3]:.6f}".replace('.', ','),
                f"{row[4]:.6f}".replace('.', ',')
            ])

    print(f"\nCSV generado: {csv_filename}\n")


if __name__ == "__main__":
    main()
