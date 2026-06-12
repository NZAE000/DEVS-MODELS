#!/usr/bin/env python3

import argparse
import re
from collections import defaultdict

import numpy as np
import pandas as pd

from scipy.stats import pearsonr
from scipy.stats import spearmanr

from sklearn.metrics import (
    r2_score,
    mean_absolute_error,
    mean_squared_error
)

def read_utilization_file(filename):

    data = defaultdict(dict)
    current_rate = None

    with open(filename, "r") as f:

        for line in f:
            line = line.strip()
            if not line:
                continue

            #
            # Rate line
            #
            if ":" not in line:
                current_rate = int(line)
                continue

            operator, values = line.split(":", 1)
            match = re.search(r"\[(.*?)\]", values)

            if not match:
                continue

            utilizations = [
                float(x)
                for x in match.group(1).split()
            ]

            data[current_rate][operator] = utilizations

    return data

def compute_metrics(real_values, sim_values):


    period_real = np.linspace(0.0, 1.0, len(real_values))
    period_sim = np.linspace(0.0, 1.0, len(sim_values))

    common_period = np.linspace(
        0.0,
        1.0,
        max(len(real_values), len(sim_values))
    )

    real_interp = np.interp(common_period, period_real, real_values)
    sim_interp  = np.interp(common_period, period_sim, sim_values)

    #
    # Pearson / Spearman
    #
    EPS = 1e-12

    if (np.std(real_interp) < EPS or np.std(sim_interp) < EPS):

        if np.allclose(real_interp, sim_interp):
            pearson = 1.0
            spearman = 1.0
        else:
            pearson = np.nan
            spearman = np.nan

    else:

        pearson = pearsonr(real_interp, sim_interp)[0]
        spearman = spearmanr(real_interp, sim_interp)[0]

    #
    # Regression metrics
    #
    r2 = r2_score(real_interp, sim_interp)

    mae = mean_absolute_error(real_interp, sim_interp)

    rmse = np.sqrt(
        mean_squared_error(
            real_interp,
            sim_interp
        )
    )

    #
    # MAPE
    #
    nonzero_mask = (np.abs(real_interp) > EPS)

    if np.any(nonzero_mask):

        mape = np.mean(
            np.abs(
                (
                    real_interp[nonzero_mask]
                    - sim_interp[nonzero_mask]
                )
                /
                real_interp[nonzero_mask]
            )
        ) * 100.0

    else:
        mape = np.nan

    max_error = np.max(
        np.abs(
            real_interp
            - sim_interp
        )
    )

    #
    # Area under curve
    #
    auc_real = np.trapezoid(real_interp, common_period)
    auc_sim = np.trapezoid(sim_interp, common_period)

    if auc_real > EPS:
        auc_error_pct = (
            abs(
                auc_real
                - auc_sim
            )
            /
            auc_real
        ) * 100.0

    else:
        auc_error_pct = np.nan

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
    parser.add_argument("nodes", type=int)
    parser.add_argument("cores", type=int)
    parser.add_argument("p", type=int)

    args = parser.parse_args()

    filename_real = (
        f"metrics/nexmark/utilization/real/dynamic/"
        f"dynamic-utilization-real-"
        f"{args.app}-"
        f"{args.nodes}-"
        f"{args.cores}-"
        f"{args.p}.txt"
    )

    filename_sim = (
        f"metrics/nexmark/utilization/sim/dynamic/"
        f"dynamic-utilization-sim-"
        f"{args.app}-"
        f"{args.nodes}-"
        f"{args.cores}-"
        f"{args.p}.txt"
    )

    output_file = (
        f"metrics/nexmark/utilization/"
        f"statistics-real-sim/dynamic/"
        f"dynamic-utilization-real-sim-statistics-"
        f"{args.app}-"
        f"{args.nodes}-"
        f"{args.cores}-"
        f"{args.p}.csv"
    )

    real_data  = read_utilization_file(filename_real)
    sim_data   = read_utilization_file(filename_sim)
    rates_real = sorted(real_data.keys())
    rates_sim  = sorted(sim_data.keys())

    if rates_real != rates_sim:
        raise ValueError(
            "Real and simulated files "
            "contain different rates"
        )

    #
    # Validate operators
    #
    for rate in rates_real:
        real_ops = set(real_data[rate].keys())
        sim_ops  = set(sim_data[rate].keys())

        if real_ops != sim_ops:
            raise ValueError(f"Different operators "f"for rate {rate}")

    results = []

    for rate in rates_real:
        for operator in sorted(real_data[rate].keys()):
            metrics = compute_metrics(real_data[rate][operator], sim_data[rate][operator])
            results.append({"rate": rate, "operator": operator, **metrics})

    df = pd.DataFrame(results)
    df.to_csv(output_file, index=False)

    print()
    print("=" * 49)
    print("UTILIZATION VALIDATION")
    print("=" * 49)
    print()
    print(f"Operators analyzed : "f"{len(real_data[rates_real[0]])}")
    print(f"Rates analyzed     : "f"{len(rates_real)}")
    print(f"Comparisons        : "f"{len(df)}")
    print()
    print(f"Average Pearson : "f"{df['pearson'].mean():.3f}")
    print(f"Average Spearman: "f"{df['spearman'].mean():.3f}")
    print(f"Average R²      : "f"{df['r2'].mean():.3f}")
    print(f"Average MAE     : "f"{df['mae'].mean():.6f}")
    print(f"Average RMSE    : "f"{df['rmse'].mean():.6f}")
    print(f"Average MAPE    : "f"{df['mape'].mean():.2f}%")
    print()
    print(f"Average AUC Error: "f"{df['auc_error_pct'].mean():.2f}%")
    print("=" * 49)
    print()
    print(f"CSV saved in: "f"{output_file}")

if __name__ == "__main__":
    main()
