#!/usr/bin/env python3

import argparse
import re
from collections import defaultdict
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

plt.style.use("metrics/thesis.mplstyle")

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


def plot_utilization_comparison(rates, operators, real_data, sim_data, app, nodes, cores, p):
    fig, ax = plt.subplots()

    cmap = plt.get_cmap("tab20")
    base_colors = [cmap(i % cmap.N) for i in range(len(operators))]

    for i, operator in enumerate(operators):
        color = base_colors[i]
        x_real, y_real = [], []
        x_sim, y_sim = [], []

        interval_start = 0.0
        for rate in rates:
            samples = real_data[operator][rate]
            n = len(samples)

            if n == 1:
                x_real.append(interval_start + 0.5)
                y_real.append(samples[0])
            else:
                for idx, util in enumerate(samples):
                    x_real.append(interval_start + idx / (n - 1))
                    y_real.append(util)

            interval_start += 1.0

        interval_start = 0.0
        for rate in rates:
            samples = sim_data[operator][rate]
            n = len(samples)

            if n == 1:
                x_sim.append(interval_start + 0.5)
                y_sim.append(samples[0])
            else:
                for idx, util in enumerate(samples):
                    x_sim.append(interval_start + idx / (n - 1))
                    y_sim.append(util)

            interval_start += 1.0

        ax.plot(
            x_real,
            y_real,
            color=color,
            linestyle="-",
            linewidth=2.8,
            alpha=1.0,
            zorder=3
        )

        ax.plot(
            x_sim,
            y_sim,
            color=color,
            linestyle=(0, (6, 3)),
            linewidth=2.8,
            alpha=0.65,
            zorder=2
        )

    # Líneas divisorias entre tasas.
    for boundary in range(len(rates) + 1):
        ax.axvline(
            x=boundary,
            linestyle=":",
            color="black",
            linewidth=1
        )

    # Etiquetas inferiores de las tasas.
    rate_labels = []

    for idx, rate in enumerate(rates):
        annotation = ax.annotate(
            f"{rate / 1e6:.0f}M",
            xy=(idx + 0.5, 0),
            xycoords=("data", "axes fraction"),
            xytext=(0, -25),
            textcoords="offset points",
            ha="center",
            va="top",
            fontsize=16,
            fontweight="bold",
            annotation_clip=False,
            clip_on=False
        )
        rate_labels.append(annotation)

    rate_annotation = ax.annotate(
        "Rate (req/s)",
        xy=(0, 0),
        xycoords=("axes fraction", "axes fraction"),
        xytext=(0, -25),
        textcoords="offset points",
        ha="right",
        va="top",
        fontsize=16,
        fontweight="bold",
        annotation_clip=False,
        clip_on=False
    )

    # Eje X.
    xticks = []
    xticklabels = []

    for i in range(len(rates)):
        for frac in [0.0, 0.2, 0.4, 0.6, 0.8]:
            xticks.append(i + frac)
            xticklabels.append(f"{frac:.1f}")

    xticks.append(len(rates))
    xticklabels.append("1.0")

    ax.set_xticks(xticks)
    ax.set_xticklabels(xticklabels)
    ax.set_xlim(0, len(rates))
    ax.set_ylim(0, 1.0)

    ax.set_xlabel("Time Period", labelpad=40)
    ax.set_ylabel("Utilization")
    ax.set_title(
        "Dynamic Operator Utilization: Real vs Simulated\n"
        f"App={app}, Nodes={nodes}, Cores={cores}, P={p}"
    )
    ax.grid(True)

    # Leyenda de operadores.
    operator_handles = []

    for i, operator in enumerate(operators):
        color = base_colors[i]
        operator_handles.append(
            Line2D(
                [0],
                [0],
                marker="s",
                linestyle="None",
                markerfacecolor=color,
                markeredgecolor=color,
                markersize=10,
                label=operator
            )
        )

    legend_ops = ax.legend(
        handles=operator_handles,
        loc="upper center",
        bbox_to_anchor=(0.5, -0.25),
        ncol=min(4, len(operators)),
        frameon=True
    )
    ax.add_artist(legend_ops)

    # Leyenda de estilos.
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

    ax.legend(
        handles=style_handles,
        loc="upper right",
        frameon=True
    )

    fig.subplots_adjust(
        left=0.12,
        right=0.98,
        bottom=0.32,
        top=0.88
    )

    output_file = (
        "metrics/nexmark/utilization/"
        "plot-real-sim/dynamic/"
        f"dynamic-utilization-real-sim-{app}-{nodes}-{cores}-{p}"
    )

    extra_artists = (
        legend_ops,
        rate_annotation,
        *rate_labels
    )

    fig.savefig(
        f"{output_file}.pdf",
        bbox_extra_artists=extra_artists
    )

    fig.savefig(
        f"{output_file}.png",
        bbox_extra_artists=extra_artists
    )

    plt.show()
    #plt.close(fig)

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