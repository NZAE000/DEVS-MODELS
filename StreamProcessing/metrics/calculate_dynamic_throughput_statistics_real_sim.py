#!/usr/bin/env python3

import argparse
import csv

import numpy as np

from scipy.interpolate import interp1d
from scipy.stats import pearsonr
from scipy.stats import spearmanr

from sklearn.metrics import (
    mean_absolute_error,
    mean_squared_error,
    r2_score
)


def read_file(filename):

    rate_data = {}
    with open(filename, "r") as f:

        for line in f:
            line = line.strip()
            if not line:
                continue

            rate_part, data_part = line.split(":", 1)
            rate = int(rate_part)
            samples = []

            for token in data_part.split():
                time_str, throughput_str = token.split(",")
                samples.append(
                    (
                        float(time_str),
                        float(throughput_str)
                    )
                )

            rate_data[rate] = samples

    return rate_data


def compute_metrics(
    real_samples,
    sim_samples,
    interpolation_points=1000
):

    #
    # Ordenar por tiempo
    #
    real_samples = sorted(real_samples)
    sim_samples  = sorted(sim_samples)

    real_time = np.array([x[0] for x in real_samples])
    real_thr  = np.array([x[1] for x in real_samples])
    sim_time  = np.array([x[0] for x in sim_samples])
    sim_thr   = np.array([x[1] for x in sim_samples])
    
    #
    # Rango común
    #
    start_time = max(real_time.min(), sim_time.min())
    end_time   = min(real_time.max(), sim_time.max())

    if end_time <= start_time:
        raise ValueError(
            "No overlapping time interval."
        )

    common_time = np.linspace(
        start_time,
        end_time,
        interpolation_points
    )

    #
    # Interpolación
    #
    real_interp = interp1d(real_time, real_thr,kind="linear")
    sim_interp  = interp1d(sim_time, sim_thr, kind="linear")
    real_values = real_interp(common_time)
    sim_values  = sim_interp(common_time)

    #
    # Correlaciones
    #
    pearson  = pearsonr(real_values, sim_values)[0]
    spearman = spearmanr(real_values, sim_values)[0]

    #
    # Errores
    #
    mae = mean_absolute_error(real_values, sim_values)

    rmse = np.sqrt(
        mean_squared_error(
            real_values,
            sim_values
        )
    )

    #
    # MAPE
    #
    non_zero = real_values != 0

    mape = np.mean(
        np.abs(
            (
                real_values[non_zero]
                - sim_values[non_zero]
            )
            /
            real_values[non_zero]
        )
    ) * 100.0

    #
    # R²
    #
    r2 = r2_score(real_values, sim_values)

    #
    # Error máximo
    #
    max_error = np.max(
        np.abs(
            real_values
            - sim_values
        )
    )

    #
    # AUC
    #
    auc_real = np.trapezoid(real_values, common_time)
    auc_sim  = np.trapezoid(sim_values, common_time)

    auc_error_pct = (
        abs(
            auc_real
            - auc_sim
        )
        /
        auc_real
    ) * 100.0

    return {
        "pearson": pearson,
        "spearman": spearman,
        "r2": r2,
        "mae": mae,
        "rmse": rmse,
        "mape": mape,
        "max_error": max_error,
        "auc_real": auc_real,
        "auc_sim": auc_sim,
        "auc_error_pct": auc_error_pct
    }


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("app")
    parser.add_argument("nodes")
    parser.add_argument("cores")
    parser.add_argument("p")

    args = parser.parse_args()

    filename_real = (
        f"metrics/nexmark/throughput/real/dynamic/"
        f"dynamic-throughput-real-"
        f"{args.app}-{args.nodes}-"
        f"{args.cores}-{args.p}.txt"
    )

    filename_sim = (
        f"metrics/nexmark/throughput/sim/dynamic/"
        f"dynamic-throughput-sim-"
        f"{args.app}-{args.nodes}-"
        f"{args.cores}-{args.p}.txt"
    )

    csv_output = (
        f"metrics/nexmark/throughput/statistics-real-sim/dynamic/"
        f"dynamic-throughput-real-sim-statics-"
        f"{args.app}-{args.nodes}-"
        f"{args.cores}-{args.p}.csv"
    )

    real_data = read_file(filename_real)
    sim_data  = read_file(filename_sim)

    if (
        sorted(real_data.keys())
        !=
        sorted(sim_data.keys())
    ):
        raise ValueError(
            "Files contain different rates."
        )

    metrics_list = []

    with open(csv_output, "w", newline="") as csvfile:

        writer = csv.writer(csvfile)

        writer.writerow([
            "rate",
            "pearson",
            "spearman",
            "r2",
            "mae",
            "rmse",
            "mape",
            "max_error",
            "auc_real",
            "auc_sim",
            "auc_error_pct"
        ])

        for rate in sorted(real_data.keys()):

            metrics = compute_metrics(real_data[rate], sim_data[rate])
            metrics_list.append(metrics)

            writer.writerow([
                rate,
                metrics["pearson"],
                metrics["spearman"],
                metrics["r2"],
                metrics["mae"],
                metrics["rmse"],
                metrics["mape"],
                metrics["max_error"],
                metrics["auc_real"],
                metrics["auc_sim"],
                metrics["auc_error_pct"]
            ])

    #
    # Resumen
    #
    avg_pearson = np.mean([m["pearson"] for m in metrics_list])
    avg_spearman = np.mean([m["spearman"] for m in metrics_list])
    avg_r2 = np.mean([m["r2"] for m in metrics_list])
    avg_mae = np.mean([m["mae"] for m in metrics_list])
    avg_rmse = np.mean([m["rmse"] for m in metrics_list])
    avg_mape = np.mean([m["mape"] for m in metrics_list])
    avg_auc_error = np.mean(
        [
            m["auc_error_pct"]
            for m in metrics_list
        ]
    )

    print()
    print("=" * 49)
    print("THROUGHPUT VALIDATION")
    print("=" * 49)
    print()
    print(f"Average Pearson : "f"{avg_pearson:.4f}")
    print(f"Average Spearman: "f"{avg_spearman:.4f}")
    print(f"Average R²      : "f"{avg_r2:.4f}")
    print(f"Average MAE     : "f"{avg_mae:,.2f} req/s")
    print(f"Average RMSE    : "f"{avg_rmse:,.2f} req/s")
    print(f"Average MAPE    : "f"{avg_mape:.2f}%")
    print()
    print(f"Average AUC Error: "f"{avg_auc_error:.2f}%")

    print("=" * 49)

    print()
    print(f"CSV saved in: "f"{csv_output}")


if __name__ == "__main__":
    main()