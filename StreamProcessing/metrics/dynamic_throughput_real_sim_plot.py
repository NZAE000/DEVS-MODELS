#!/usr/bin/env python3

import argparse
import math
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter, MaxNLocator

plt.style.use("metrics/thesis.mplstyle")


def format_rate(value, _position=None):
    value = float(value)
    abs_value = abs(value)

    if abs_value >= 1_000_000:
        return f"{value / 1_000_000:g}M"
    if abs_value >= 1_000:
        return f"{value / 1_000:g}K"
    return f"{value:g}"


def read_file(filename):
    """Read independent rate occurrences in chronological order."""
    intervals = []

    with open(filename, "r", encoding="utf-8") as file:
        for line in file:
            line = line.strip()
            if not line:
                continue

            rate_text, samples_text = line.split(":", 1)
            rate = float(rate_text)
            samples = []

            for sample_text in samples_text.split():
                time_text, throughput_text = sample_text.split(",", 1)
                samples.append((float(time_text), float(throughput_text)))

            if samples:
                samples.sort(key=lambda sample: sample[0])
                intervals.append((rate, samples))

    if not intervals:
        raise ValueError(f"No valid throughput samples found in {filename}")

    intervals.sort(key=lambda interval: interval[1][0][0])
    rates = [rate for rate, _ in intervals]
    rate_data = [samples for _, samples in intervals]
    return rates, rate_data


def curve_data(rate_data):
    times = [time for samples in rate_data for time, _ in samples]
    throughputs = [throughput for samples in rate_data for _, throughput in samples]
    end_times = [samples[-1][0] for samples in rate_data]
    return times, throughputs, end_times


def draw_ideal(ax, rates, end_times, label, linestyle):
    ax.step(
        [0.0] + end_times,
        rates + [rates[-1]],
        where="post",
        linestyle=linestyle,
        color="green",
        linewidth=1.7,
        label=label,
    )


def annotate_rates(ax, rates, end_times, row, caption):
    offset = -25 - 23 * row
    start = 0.0

    for rate, end in zip(rates, end_times):
        center = (start + end) / 2.0
        ax.annotate(
            format_rate(rate),
            xy=(center, 0),
            xycoords=("data", "axes fraction"),
            xytext=(0, offset),
            textcoords="offset points",
            ha="center",
            va="top",
            fontsize="16",
            clip_on=False,
            annotation_clip=False,
        )
        start = end

    ax.annotate(
        caption,
        xy=(0, 0),
        xycoords="axes fraction",
        xytext=(-5, offset),
        textcoords="offset points",
        ha="right",
        va="top",
        fontsize="16",
        fontweight="bold",
        clip_on=False,
        annotation_clip=False,
    )


def plot_dynamic_comparison(rates, real_data, sim_data,
                            app, app_dir, nodes, cores, p):
    real_x, real_y, real_ends = curve_data(real_data)
    sim_x, sim_y, sim_ends = curve_data(sim_data)
    max_time = max(real_ends[-1], sim_ends[-1])

    fig, ax = plt.subplots()
    ax.plot(real_x, real_y, marker="o", label="Real")
    ax.plot(sim_x, sim_y, marker="o", label="Simulation")

    same_boundaries = all(
        math.isclose(tr, ts, rel_tol=0, abs_tol=1e-3)
        for tr, ts in zip(real_ends, sim_ends)
    )

    if len(rates) == 1:
        # One common ideal rate, extending to the last actual observation.
        draw_ideal(ax, rates, [max_time], "Ideal", "--")
        annotate_rates(ax, rates, [max_time], 0, "Rate (req/s)")
        two_rows = False
    elif same_boundaries:
        draw_ideal(ax, rates, real_ends, "Ideal", "--")
        annotate_rates(ax, rates, real_ends, 0, "Rate (req/s)")
        two_rows = False
    else:
        # Different rate-change times cannot share one exact ideal staircase.
        draw_ideal(ax, rates, real_ends, "Ideal (real timeline)", "--")
        draw_ideal(ax, rates, sim_ends, "Ideal (sim timeline)", ":")
        annotate_rates(ax, rates, real_ends, 0, "Real rate (req/s)")
        annotate_rates(ax, rates, sim_ends, 1, "Sim rate (req/s)")
        two_rows = True

    for boundary in sorted(set([0.0] + real_ends + sim_ends)):
        ax.axvline(boundary, linestyle=":", color="blue", alpha=0.6)

    ax.set_xlabel("Time (s)", labelpad=68 if two_rows else 40)
    ax.set_ylabel("Throughput (req/s)")
    ax.set_title(
        "Dynamic Throughput: Real vs Simulated\n"
        f"App={app}, Nodes={nodes}, Cores={cores}, P={p}"
    )
    ax.grid(True)
    ax.legend()

    # Keep intermediate interval boundaries,
    # but show only the largest final time.
    xticks = sorted(set(
        [0.0] + real_ends[:-1] + sim_ends[:-1] + [max_time]
    ))
    if len(xticks) <= 6:
        ax.set_xticks(xticks)
        ax.set_xticklabels([f"{t:.2f}s" for t in xticks], rotation=0, ha="right")
    else:
        ax.xaxis.set_major_locator(MaxNLocator(nbins=7))
        ax.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"{x:g}s"))

    ax.set_xlim(0.0, max_time)
    ax.set_yticks(sorted(set([0.0] + rates)))
    ax.yaxis.set_major_formatter(FuncFormatter(format_rate))
    ax.set_ylim(0.0, 1.05 * max(max(rates), max(real_y), max(sim_y)))

    fig.subplots_adjust(left=0.14, bottom=0.30 if two_rows else 0.19)

    output_file = (
        Path("metrics") / app_dir / "throughput" / "plot-real-sim" / "dynamic"
        / f"dynamic-throughput-real-sim-{app}-{nodes}-{cores}-{p}"
    )
    output_file.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_file.with_suffix(".pdf"), bbox_inches="tight")
    fig.savefig(output_file.with_suffix(".png"), bbox_inches="tight")
    plt.show()
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description="Plot real and simulated throughput vs time")
    parser.add_argument("app")
    parser.add_argument("app_dir")
    parser.add_argument("nodes")
    parser.add_argument("cores")
    parser.add_argument("p")
    args = parser.parse_args()

    prefix = Path("metrics") / args.app_dir / "throughput"
    suffix = f"{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    filename_real = prefix / "real" / "dynamic" / f"dynamic-throughput-real-{suffix}"
    filename_sim = prefix / "sim" / "dynamic" / f"dynamic-throughput-sim-{suffix}"

    rates_real, real_data = read_file(filename_real)
    rates_sim, sim_data = read_file(filename_sim)
    if rates_real != rates_sim:
        raise ValueError("Real and simulation files contain different rate sequences.")

    plot_dynamic_comparison(
        rates_real, real_data, sim_data,
        args.app, args.app_dir, args.nodes, args.cores, args.p,
    )


if __name__ == "__main__":
    main()
