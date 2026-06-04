#!/usr/bin/env python3

import argparse
from collections import defaultdict
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


from collections import defaultdict


from collections import defaultdict


def read_file(filename):
    """
    Retorna:

        rates_order:
            orden de las tasas

        rate_data:
            rate -> [(time, throughput), ...]
    """

    rate_data = defaultdict(list)
    rates_order = []

    with open(filename, "r") as f:

        for line in f:

            line = line.strip()

            if not line:
                continue

            rate_part, measurements = line.split(":", 1)

            rate = int(rate_part)

            rates_order.append(rate)

            for measurement in measurements.split():

                time_str, throughput_str = measurement.split("-")

                time = float(time_str)
                throughput = float(throughput_str)

                rate_data[rate].append(
                    (time, throughput)
                )

    return rates_order, rate_data


def plot_throughput(rates, rate_data, app, nodes, cores, p):

    plt.figure(figsize=(12, 7))

    #
    # Throughput ideal
    #
    plt.plot(
        rates,
        rates,
        linestyle="--",
        linewidth=2,
        label="Ideal"
    )

    #
    # Construir trayectoria observada
    #
    x_values = []
    y_values = []

    if len(rates) > 1:
        rate_spacing = rates[1] - rates[0]
    else:
        rate_spacing = rates[0]

    for idx, rate in enumerate(rates):

        samples = rate_data[rate]

        if not samples:
            continue

        times = [t for t, _ in samples]

        min_time = min(times)
        max_time = max(times)

        #
        # Definir inicio y fin del intervalo
        #
        if len(rates) == 1:

            interval_start = 0
            interval_end = rate

        else:

            interval_start = rate

            #
            # Último intervalo
            #
            if idx == len(rates) - 1:
                interval_end = rate + rate_spacing
            else:
                interval_end = rates[idx + 1]

        interval_size = (
            interval_end - interval_start
        )

        #
        # Normalizar tiempos dentro del intervalo
        #
        for time, throughput in samples:

            if max_time == min_time:
                relative_pos = 0.0
            else:
                relative_pos = (
                    (time - min_time)
                    / (max_time - min_time)
                )

            x = (
                interval_start
                + relative_pos * interval_size
            )

            x_values.append(x)
            y_values.append(throughput)

    #
    # Curva observada
    #
    plt.plot(
        x_values,
        y_values,
        marker="o",
        markersize=3,
        linewidth=1.5,
        label="Observed"
    )

    max_rate = max(rates)

    plt.ylim(0, max_rate)

    plt.xlabel("Arrival Rate (events/s)", labelpad=40)
    plt.ylabel("Throughput (events/s)")

    plt.title(
        f"Throughput vs Arrival Rate\n"
        f"App={app}, Nodes={nodes}, Cores={cores}, P={p}"
    )
    
    # Calcula el tiempo inicial de cada intervalo
    interval_start_times = {}
    for rate in rates:
        interval_start_times[rate] = min(
            time for time, _ in rate_data[rate]
        )

    plt.grid(True)
    plt.legend()
    
    #
    # Líneas verticales que separan intervalos
    #
    for rate in rates:
        plt.axvline(
            x=rate,
            linestyle=":",
            linewidth=1,
            alpha=0.4
        )

    #
    # Mostrar tiempo debajo de cada tasa
    #
    ax = plt.gca()

    time_labels = [
        f"{interval_start_times[rate]:.2f}s"
        for rate in rates
    ]

    for rate, label in zip(rates, time_labels):

        ax.annotate(
            label,
            xy=(rate, 0),
            xycoords=("data", "axes fraction"),
            xytext=(0, -25),
            textcoords="offset points",
            ha="center",
            va="top",
            fontsize=8
        )

    #
    # Etiqueta para la segunda fila
    #
    ax.annotate(
        "Time",
        xy=(0, 0),
        xycoords=("axes fraction", "axes fraction"),
        xytext=(-45, -25),
        textcoords="offset points",
        ha="right",
        va="top",
        fontsize=9,
        fontweight="bold"
    )

    formatter = FuncFormatter(
    lambda x, pos: f"{x/1e6:.0f}M"
    )

    ax = plt.gca()

    #
    # Ticks X
    #
    if len(rates) == 1:
        ax.set_xticks([0, rates[0]])
    else:
        ax.set_xticks(rates)

    #
    # Ticks Y
    #
    if len(rates) == 1:
        ax.set_yticks([0, rates[0]])
    else:
        ax.set_yticks([0] + rates)

    ax.xaxis.set_major_formatter(formatter)
    ax.yaxis.set_major_formatter(formatter)

    plt.tight_layout()
    plt.subplots_adjust(bottom=0.18)

    output_file = (
        f"metrics/nexmark/throughput/plot-sim/dynamic/"
        f"dynamic-throughput-sim-{app}-{nodes}-{cores}-{p}.png"
    )

    plt.savefig(output_file, dpi=300)
    plt.show()

    print(f"Graph saved in: {output_file}")

def main():
    parser = argparse.ArgumentParser(
        description="Plot throughput vs arrival rate"
    )

    parser.add_argument("app")
    parser.add_argument("nodes")
    parser.add_argument("cores")
    parser.add_argument("p")

    args = parser.parse_args()

    filename = (
        f"metrics/nexmark/throughput/simulated/dynamic/dynamic-throughput-sim-"
        f"{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    )

    rates, rate_data = read_file(filename)

    plot_throughput(
        rates,
        rate_data,
        args.app,
        args.nodes,
        args.cores,
        args.p
    )


if __name__ == "__main__":
    main()