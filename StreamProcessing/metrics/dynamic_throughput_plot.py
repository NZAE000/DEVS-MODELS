#!/usr/bin/env python3

import argparse
from collections import defaultdict
import sys
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

plt.style.use("metrics/thesis.mplstyle")

def read_file(filename):
    """
    Return:
        rates_order:
            order of rates

        rate_data:
            rate -> [(time, throughput), ...]
    """

    rates_order = []
    rate_data = []

    with open(filename, "r") as file:
        for line in file:
            line = line.strip()

            if not line:
                continue

            rate_text, samples_text = line.split(":", 1)
            rate = float(rate_text)
            samples = []

            for sample_text in samples_text.split():
                time_text, throughput_text = sample_text.split(",", 1)

                samples.append((float(time_text), float(throughput_text))
                )

            rates_order.append(rate)
            rate_data.append(samples)
            
    return rates_order, rate_data


def plot_throughput(rates, rate_data, app, nodes, cores, p, data_from):
    def format_rate(value, _position=None):
        value = float(value)
        abs_value = abs(value)

        if abs_value >= 1_000_000:
            scaled = value / 1_000_000
            return f"{scaled:.0f}M" if scaled.is_integer() else f"{scaled:g}M"

        if abs_value >= 1_000:
            scaled = value / 1_000
            return f"{scaled:.0f}K" if scaled.is_integer() else f"{scaled:g}K"

        return f"{value:.0f}"

    if len(rates) != len(rate_data):
        raise ValueError(
            "Each rate occurrence must have its own throughput sample list."
        )

    fig, ax = plt.subplots()
    intervals = []

    # Preserve every rate occurrence as an independent interval
    for rate, interval_samples in zip(rates, rate_data):
        samples = sorted(interval_samples, key=lambda sample: sample[0])

        if samples:
            intervals.append((float(rate), samples))

    # Restore the chronological order of the intervals
    intervals.sort(key=lambda interval: interval[1][0][0])

    if not intervals:
        raise ValueError(
            "The input file does not contain valid throughput samples."
        )

    ordered_rates = []
    x_values = []
    y_values = []
    interval_end_times = []

    # Build the observed throughput curve
    for rate, samples in intervals:
        ordered_rates.append(rate)

        for time, throughput in samples:
            x_values.append(time)
            y_values.append(throughput)

        interval_end_times.append(samples[-1][0])

    ax.plot(
        x_values,
        y_values,
        marker="o",
        label="Observed"
    )

    # Build the ideal throughput step curve
    ideal_x = [0.0]
    ideal_y = [ordered_rates[0]]

    for index in range(len(ordered_rates) - 1):
        ideal_x.append(interval_end_times[index])
        ideal_y.append(ordered_rates[index + 1])

    ideal_x.append(interval_end_times[-1])
    ideal_y.append(ordered_rates[-1])

    ax.step(
        ideal_x,
        ideal_y,
        where="post",
        linestyle="--",
        label="Ideal"
    )

    ax.set_xlabel("Time (s)", labelpad=40)
    ax.set_ylabel("Throughput (req/s)")
    ax.set_title(
        f"Dynamic {data_from} Throughput\n"
        f"App={app}, Nodes={nodes}, Cores={cores}, P={p}"
    )

    ax.grid(True)
    ax.legend()

    # Draw the interval boundaries
    boundaries = [0.0] + interval_end_times

    for boundary in boundaries:
        ax.axvline(x=boundary, linestyle=":", color="grey")

    # Draw every rate occurrence below its corresponding interval
    interval_start = 0.0

    for rate, interval_end in zip(ordered_rates, interval_end_times):
        interval_center = (
            interval_start + interval_end
        ) / 2.0

        ax.annotate(
            format_rate(rate),
            xy=(interval_center, 0),
            xycoords=("data", "axes fraction"),
            xytext=(0, -25),
            textcoords="offset points",
            ha="center",
            va="top",
            color="red"
        )

        interval_start = interval_end

    rate_label = ax.annotate(
        "Rate (req/s)",
        xy=(0, 0),
        xycoords=("axes fraction", "axes fraction"),
        xytext=(-5, -25),
        textcoords="offset points",
        ha="right",
        va="top",
        fontweight="bold",
        color="red",
        clip_on=False,
        annotation_clip=False
    )

    # Show accumulated times on the X axis
    xticks = [0.0] + interval_end_times

    ax.set_xticks(xticks)
    ax.set_xticklabels(
        [f"{time:.2f}s" for time in xticks]
    )
    ax.set_xlim(0.0, interval_end_times[-1])

    # Show the arrival-rate levels on the Y axis
    y_ticks = sorted(set([0.0] + ordered_rates))

    ax.set_yticks(y_ticks)
    ax.yaxis.set_major_formatter(FuncFormatter(format_rate))
    ax.set_ylim(0.0, max(ordered_rates) * 1.05)

    fig.subplots_adjust(left=0.14, bottom=0.18)

    output_file = (
        f"metrics/nexmark/throughput/"
        f"plot-{data_from}/dynamic/"
        f"dynamic-throughput-{data_from}-"
        f"{app}-{nodes}-{cores}-{p}"
    )

    fig.savefig(f"{output_file}.pdf", bbox_extra_artists=(rate_label,))
    fig.savefig(f"{output_file}.png", bbox_extra_artists=(rate_label,))

    plt.show()
    #print(f"Graph saved in: "f"{output_file}")

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