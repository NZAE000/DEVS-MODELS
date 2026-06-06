#!/usr/bin/env python3

import argparse
import re
from collections import defaultdict

import matplotlib.pyplot as plt
import numpy as np


def read_file(filename):

    with open(filename, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    rates = []
    operators = []
    operator_data = defaultdict(dict)

    i = 0

    while i < len(lines):

        rate = int(lines[i])
        rates.append(rate)
        i += 1

        while i < len(lines):

            #
            # Nuevo bloque
            #
            if re.fullmatch(r"\d+", lines[i]):
                break

            operator, values = lines[i].split(":", 1)

            if operator not in operators:
                operators.append(operator)

            block = re.search(r"\[(.*)\]", values).group(1)

            utilizations = [
                float(x)
                for x in block.split()
            ]

            operator_data[operator][rate] = utilizations

            i += 1

    return rates, operators, operator_data


def plot_utilization_comparison(
    rates,
    operators,
    real_data,
    sim_data,
    app,
    nodes,
    cores,
    p
):

    fig, ax = plt.subplots(
        figsize=(15, 8)
    )

    #
    # Curvas
    #
    for operator in operators:

        #
        # REAL
        #
        x_real = []
        y_real = []

        interval_start = 0.0

        for rate in rates:

            samples = real_data[operator][rate]

            n = len(samples)

            if n == 1:
                x_real.append(interval_start)
                y_real.append(samples[0])

            else:

                for idx, util in enumerate(samples):

                    x = (
                        interval_start
                        + idx / (n - 1)
                    )

                    x_real.append(x)
                    y_real.append(util)

            interval_start += 1.0

        #
        # SIMULATED
        #
        x_sim = []
        y_sim = []

        interval_start = 0.0

        for rate in rates:

            samples = sim_data[operator][rate]

            n = len(samples)

            if n == 1:
                x_sim.append(interval_start)
                y_sim.append(samples[0])

            else:

                for idx, util in enumerate(samples):

                    x = (
                        interval_start
                        + idx / (n - 1)
                    )

                    x_sim.append(x)
                    y_sim.append(util)

            interval_start += 1.0

        #
        # Dibujar
        #
        ax.plot(
            x_real,
            y_real,
            linestyle="--",
            linewidth=2,
            label=f"{operator} (Real)"
        )

        ax.plot(
            x_sim,
            y_sim,
            linewidth=2,
            label=f"{operator} (Sim)"
        )

    #
    # Separadores
    #
    for x in range(len(rates) + 1):

        ax.axvline(
            x=x,
            linestyle=":",
            linewidth=1,
            alpha=0.3
        )

    #
    # Etiquetas inferiores (tasas)
    #
    for idx, rate in enumerate(rates):

        center = idx + 0.5

        ax.annotate(
            f"{rate/1e6:.0f}M",
            xy=(center, 0),
            xycoords=("data", "axes fraction"),
            xytext=(0, -25),
            textcoords="offset points",
            ha="center",
            va="top",
            fontsize=8,
            fontweight="bold"
        )

    ax.annotate(
        "Rate (req/s)",
        xy=(0, 0),
        xycoords=("axes fraction",
                  "axes fraction"),
        xytext=(-35, -25),
        textcoords="offset points",
        ha="right",
        va="top",
        fontsize=9,
        fontweight="bold"
    )

    #
    # Eje X
    #
    xticks = []

    xticklabels = []

    for i in range(len(rates)):

        for frac in [0.0, 0.2, 0.4, 0.6, 0.8]:

            xticks.append(i + frac)
            xticklabels.append(
                f"{frac:.1f}"
            )

    xticks.append(len(rates))
    xticklabels.append("1.0")

    ax.set_xticks(xticks)
    ax.set_xticklabels(
        xticklabels,
        rotation=0
    )

    ax.set_xlim(
        0,
        len(rates)
    )

    ax.set_ylim(
        0,
        1.0
    )

    ax.set_xlabel(
        "Time Period",
        labelpad=40
    )

    ax.set_ylabel(
        "Utilization"
    )

    ax.set_title(
        f"Operator Utilization: Real vs Simulated\n"
        f"App={app}, Nodes={nodes}, "
        f"Cores={cores}, P={p}"
    )

    ax.grid(True)

    plt.legend(
        loc="upper center",
        bbox_to_anchor=(0.5, -0.18),
        ncol=3
    )

    plt.tight_layout()
    plt.subplots_adjust(
        bottom=0.25
    )

    output_file = (
        "metrics/nexmark/utilization/"
        "plot-real-sim/dynamic/"
        f"dynamic-utilization-real-sim-"
        f"{app}-{nodes}-{cores}-{p}.png"
    )

    plt.savefig(output_file, dpi=300, bbox_inches="tight")
    plt.show()
    print(f"Graph saved in: {output_file}")


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("app")
    parser.add_argument("nodes")
    parser.add_argument("cores")
    parser.add_argument("p")

    args = parser.parse_args()

    filename_real = (
        f"metrics/nexmark/utilization/real/dynamic/"
        f"dynamic-utilization-real-"
        f"{args.app}-{args.nodes}-"
        f"{args.cores}-{args.p}.txt"
    )

    filename_sim = (
        f"metrics/nexmark/utilization/sim/dynamic/"
        f"dynamic-utilization-sim-"
        f"{args.app}-{args.nodes}-"
        f"{args.cores}-{args.p}.txt"
    )

    rates_real, ops_real, real_data = read_file(filename_real)
    rates_sim, ops_sim, sim_data = read_file(filename_sim)

    #
    # Validaciones
    #
    if rates_real != rates_sim:
        raise ValueError(
            "Real and simulated files "
            "have different arrival rates."
        )

    if ops_real != ops_sim:
        raise ValueError(
            "Real and simulated files "
            "have different operators."
        )

    plot_utilization_comparison(
        rates_real,
        ops_real,
        real_data,
        sim_data,
        args.app,
        args.nodes,
        args.cores,
        args.p
    )


if __name__ == "__main__":
    main()