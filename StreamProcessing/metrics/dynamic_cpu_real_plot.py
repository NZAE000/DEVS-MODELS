#!/usr/bin/env python3

import argparse
import matplotlib.pyplot as plt


def read_file(filename):

    rate_data = {}
    rates = []

    with open(filename, "r") as f:

        for line in f:
            line = line.strip()
            if not line:
                continue

            rate_part, measurements = line.split(":", 1)
            rate = int(rate_part)
            rates.append(rate)
            samples = []

            for measurement in measurements.split():

                time_str, cpu_str = measurement.split(",")
                samples.append((float(time_str), float(cpu_str)))

            rate_data[rate] = samples

    return rates, rate_data


def plot_cpu_util(rates, rate_data, app, nodes, cores, p):

    plt.figure(figsize=(12, 7))
    ax = plt.gca()

    #
    # Curva observada
    #
    x_values = []
    y_values = []
    interval_end_times = []

    for rate in rates:

        samples = sorted(rate_data[rate], key=lambda x: x[0])

        if not samples:
            continue

        for time, cpu in samples:
            x_values.append(time)
            y_values.append(cpu)

        interval_end_times.append(samples[-1][0])

    plt.plot(
        x_values,
        y_values,
        marker="o",
        markersize=3,
        linewidth=1.5,
        label="CPU Utilization"
    )

    #
    # Formato gráfico
    #
    plt.xlabel("Time (s)", labelpad=40)
    plt.ylabel("CPU Utilization (%)")

    plt.ylim(0, 100)

    plt.title(
        f"CPU Utilization vs Time\n"
        f"App={app}, "
        f"Nodes={nodes}, "
        f"Cores={cores}, "
        f"P={p}"
    )

    plt.grid(True)
    plt.legend()

    #
    # Líneas verticales
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
            xy=(
                center,
                0
            ),
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
    # Eje X
    #
    xticks = [0.0] + interval_end_times
    ax.set_xticks(xticks)

    ax.set_xticklabels([f"{t:.2f}s" for t in xticks])
    
    plt.tight_layout()
    
    plt.subplots_adjust(bottom=0.18)

    output_file = (
        "metrics/nexmark/cpu_util/"
        "plot-real/dynamic/"
        f"dynamic-cpu-real-"
        f"{app}-"
        f"{nodes}-"
        f"{cores}-"
        f"{p}.png"
    )

    plt.savefig(output_file, dpi=300)
    plt.show()
    print(f"Graph saved in: " f"{output_file}")


def main():

    parser = argparse.ArgumentParser()
    
    parser.add_argument("app")
    parser.add_argument("nodes")
    parser.add_argument("cores")
    parser.add_argument("p")

    args = parser.parse_args()

    filename = (
        f"metrics/nexmark/cpu_util/real/dynamic/dynamic-cpu-real-"
        f"{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    )

    rates, rate_data = read_file(filename)

    plot_cpu_util(
        rates,
        rate_data,
        args.app,
        args.nodes,
        args.cores,
        args.p
    )


if __name__ == "__main__":
    main()