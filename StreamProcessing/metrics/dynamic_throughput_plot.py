#!/usr/bin/env python3

import argparse
from collections import defaultdict
import sys
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


def read_file(filename):
    """
    Return:
        rates_order:
            order of rates

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

                time_str, throughput_str = measurement.split(",")
                time = float(time_str)
                throughput = float(throughput_str)

                rate_data[rate].append((time, throughput))

    return rates_order, rate_data


def plot_throughput(
    rates,
    rate_data,
    app,
    nodes,
    cores,
    p,
    data_from
):

    plt.figure(figsize=(12, 7))
    ax = plt.gca()

    #
    # Curva observada
    #
    x_values = []
    y_values = []

    interval_end_times = []

    for rate in rates:
        
        samples = sorted(rate_data[rate],key=lambda x: x[0])
        if not samples:
            continue

        for time, throughput in samples:
            x_values.append(time)
            y_values.append(throughput)

        interval_end_times.append(samples[-1][0])

    #
    # Throughput observado
    #
    plt.plot(
        x_values,
        y_values,
        marker="o",
        markersize=3,
        linewidth=1.5,
        label="Observed"
    )

    #
    # Throughput ideal
    #
    ideal_x = [0.0]
    ideal_y = [rates[0]]

    for i in range(len(rates) - 1):
        ideal_x.append(interval_end_times[i])
        ideal_y.append(rates[i + 1])

    # Extender el último escalón
    ideal_x.append(interval_end_times[-1])
    ideal_y.append(rates[-1])

    plt.step(
        ideal_x,
        ideal_y,
        where="post",
        linestyle="--",
        linewidth=2,
        label="Ideal"
    )

    plt.xlabel("Time (s)",labelpad=40)
    plt.ylabel("Throughput (req/s)")
    plt.title(
        f"Throughput vs Time\n"
        f"App={app}, "
        f"Nodes={nodes}, "
        f"Cores={cores}, "
        f"P={p}"
    )

    plt.grid(True)
    plt.legend()

    #
    # Líneas verticales de cambio de tasa
    #
    plt.axvline(
        x=0,
        linestyle=":",
        linewidth=1,
        alpha=0.4
    )

    for end_time in interval_end_times:
        plt.axvline(
            x=end_time,
            linestyle=":",
            linewidth=1,
            alpha=0.4
        )

    #
    # Segunda fila: Arrival Rates
    #
    interval_start = 0.0

    for rate, interval_end in zip(rates, interval_end_times):
        center = (interval_start + interval_end) / 2.0

        ax.annotate(
            f"{rate/1e6:.0f}M",
            xy=(center, 0),
            xycoords=(
                "data",
                "axes fraction"
            ),
            xytext=(0, -25),
            textcoords="offset points",
            ha="center",
            va="top",
            fontsize=8,
            fontweight="bold"
        )

        interval_start = interval_end

    #
    # Etiqueta segunda fila
    #
    ax.annotate(
        "Rate (req/s)",
        xy=(0, 0),
        xycoords=(
            "axes fraction",
            "axes fraction"
        ),
        xytext=(-35, -25),
        textcoords="offset points",
        ha="right",
        va="top",
        fontsize=9,
        fontweight="bold"
    )

    #
    # Eje X: tiempos reales
    #
    xticks = [0.0] + interval_end_times

    ax.set_xticks(xticks)
    ax.set_xticklabels([f"{t:.2f}s" for t in xticks])

    #
    # Eje Y
    #
    formatter = FuncFormatter(lambda x, pos:f"{x/1e6:.0f}M")

    if len(rates) == 1:
        ax.set_yticks([0, rates[0]])
    else:
        ax.set_yticks([0] + rates)

    ax.yaxis.set_major_formatter(formatter)

    plt.tight_layout()
    plt.subplots_adjust(bottom=0.18)

    output_file = (
        f"metrics/nexmark/throughput/"
        f"plot-{data_from}/dynamic/"
        f"dynamic-throughput-"
        f"{data_from}-"
        f"{app}-"
        f"{nodes}-"
        f"{cores}-"
        f"{p}.png"
    )

    plt.savefig(
        output_file,
        dpi=300
    )

    plt.show()
    print(f"Graph saved in: "f"{output_file}")

def main():
    parser = argparse.ArgumentParser(
        description="Plot throughput vs Time"
    )

    parser.add_argument("app")
    parser.add_argument("nodes")
    parser.add_argument("cores")
    parser.add_argument("p")
    parser.add_argument("data_from")

    args = parser.parse_args()
    
    if args.data_from != "real" and args.data_from != "sim":
        print("Data must be real or sim")
        sys.exit(1)

    filename = (
        f"metrics/nexmark/throughput/{f"{args.data_from}"}/dynamic/dynamic-throughput-"
        f"{args.data_from}-{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    )

    rates, rate_data = read_file(filename)

    plot_throughput(
        rates,
        rate_data,
        args.app,
        args.nodes,
        args.cores,
        args.p,
        args.data_from
    )


if __name__ == "__main__":
    main()