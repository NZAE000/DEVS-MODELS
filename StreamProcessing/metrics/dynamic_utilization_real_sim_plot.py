#!/usr/bin/env python3
"""Plot dynamic operator utilization on normalized time intervals."""

import argparse
import re
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

plt.style.use("metrics/thesis.mplstyle")


def format_rate(value):
    """Return a compact rate label, without rounding 1.5M to 2M."""
    value = float(value)
    if abs(value) >= 1_000_000:
        return f"{value / 1_000_000:g}M"
    if abs(value) >= 1_000:
        return f"{value / 1_000:g}K"
    return f"{value:g}"


def read_file(filename):
    """
    Read rate/operador:[values] blocks.

    Returns rates, operators, and samples indexed by operator + period index.
    The period index is important when the same arrival rate occurs twice.
    """
    rates = []
    operators = []
    data = defaultdict(dict)
    interval = None

    with open(filename, "r", encoding="utf-8") as source:
        for line_no, raw_line in enumerate(source, start=1):
            line = raw_line.strip()
            if not line:
                continue

            if re.fullmatch(r"\d+(?:\.\d+)?", line):
                rate = float(line) if "." in line else int(line)
                rates.append(rate)
                interval = len(rates) - 1
                continue

            if interval is None or ":" not in line:
                raise ValueError(f"{filename}:{line_no}: invalid data line: {line!r}")

            operator, values = line.split(":", 1)
            operator = operator.strip()
            match = re.fullmatch(r"\s*\[(.*?)\]\s*", values)
            if not operator or match is None:
                raise ValueError(
                    f"{filename}:{line_no}: expected 'operator:[values]'"
                )
            samples = [float(item) for item in match.group(1).split()]
            if not samples:
                raise ValueError(f"{filename}:{line_no}: empty samples for {operator}")
            if interval in data[operator]:
                raise ValueError(
                    f"{filename}:{line_no}: operator {operator!r} duplicated "
                    f"within period {interval + 1}"
                )
            if operator not in operators:
                operators.append(operator)
            data[operator][interval] = samples

    if not rates:
        raise ValueError(f"{filename}: no arrival-rate periods")

    for operator in operators:
        missing = [i + 1 for i in range(len(rates)) if i not in data[operator]]
        if missing:
            raise ValueError(
                f"{filename}: operator {operator!r} missing in periods {missing}"
            )

    return rates, operators, data


def period_xy(index, samples):
    """Map the samples in a period to the interval [index, index + 1]."""
    if len(samples) == 1:
        return [index + 0.5], samples
    return (
        [index + j / (len(samples) - 1) for j in range(len(samples))],
        samples,
    )


def configure_axes(ax, rates, max_utilization, app, nodes, cores, p, title):
    for boundary in range(len(rates) + 1):
        ax.axvline(boundary, color="grey", linestyle=":", linewidth=1, zorder=1)

    rate_labels = []
    for index, rate in enumerate(rates):
        rate_labels.append(
            ax.annotate(
                format_rate(rate),
                xy=(index + 0.5, 0),
                xycoords=("data", "axes fraction"),
                xytext=(0, -25),
                textcoords="offset points",
                ha="center", va="top", fontsize=16, fontweight="bold",
                annotation_clip=False, clip_on=False,
            )
        )

    rate_title = ax.annotate(
        "Rate (req/s)",
        xy=(0, 0), xycoords="axes fraction",
        xytext=(-5, -25), textcoords="offset points",
        ha="right", va="top", fontsize=16, fontweight="bold",
        annotation_clip=False, clip_on=False,
    )

    xticks, labels = [], []
    for index in range(len(rates)):
        for frac in (0.0, 0.2, 0.4, 0.6, 0.8):
            xticks.append(index + frac)
            labels.append(f"{frac:.1f}")
    xticks.append(len(rates))
    labels.append("1.0")
    ax.set_xticks(xticks, labels=labels)
    ax.set_xlim(0, len(rates))

    # A small visual headroom is necessary: values at 1.0 otherwise disappear
    # into the top frame, and floating-point noise can exceed 1.0 slightly.
    ax.set_ylim(0, max(1.025, max_utilization + 0.02))
    ax.set_yticks([0, 0.2, 0.4, 0.6, 0.8, 1.0])
    ax.set_xlabel("Time Period", labelpad=40)
    ax.set_ylabel("Utilization")
    ax.set_title(
        f"{title}\nApp={app}, Nodes={nodes}, Cores={cores}, P={p}"
    )
    ax.set_axisbelow(True)
    ax.grid(True)
    return [rate_title, *rate_labels]


def operator_legend_handles(operators, colors):
    return [
        Line2D(
            [0], [0], marker="s", linestyle="None", markersize=10,
            markerfacecolor=color, markeredgecolor=color, label=operator,
        )
        for operator, color in zip(operators, colors)
    ]


def position_legend_and_axes(fig, ax, operators, colors):
    """
    Reserve measured space for the operator legend outside the plot.

    Dynamically choose legend columns that fit the page. Enlarge the canvas
    as the number of rows grows, keeping the graph itself at a constant height.
    """
    width = max(float(plt.rcParams["figure.figsize"][0]), 10.0)
    fig.set_size_inches(width, 8.0)
    handles = operator_legend_handles(operators, colors)
    legend = None
    for ncol in range(min(4, len(operators)), 0, -1):
        if legend is not None:
            legend.remove()
        legend = fig.legend(
            handles=handles, loc="lower center",
            bbox_to_anchor=(0.5, 0), bbox_transform=fig.transFigure,
            ncol=ncol, frameon=True,
        )
        fig.canvas.draw()
        legend_width = legend.get_window_extent(
            renderer=fig.canvas.get_renderer()
        ).width / fig.dpi
        if legend_width < width - 0.5:
            break

    fig.canvas.draw()
    legend_height = legend.get_window_extent(
        renderer=fig.canvas.get_renderer()
    ).height / fig.dpi

    legend_bottom_in = 0.18
    space_for_labels_in = 1.52
    axes_height_in = 4.65
    top_margin_in = 0.95
    axes_bottom_in = legend_bottom_in + legend_height + space_for_labels_in
    height = axes_bottom_in + axes_height_in + top_margin_in
    fig.set_size_inches(width, height)

    # The graph remains 4.65 inches tall for 2, 6, or 16 operators.
    left_in, right_in = 1.12, 0.35
    ax.set_position([
        left_in / width, axes_bottom_in / height,
        (width - left_in - right_in) / width, axes_height_in / height,
    ])
    legend.set_bbox_to_anchor(
        (0.5, legend_bottom_in / height), transform=fig.transFigure
    )
    return legend


def save_plot(fig, output_file, extra_artists):
    path = Path(output_file)
    path.parent.mkdir(parents=True, exist_ok=True)
    for extension in ("pdf", "png"):
        fig.savefig(
            f"{path}.{extension}", bbox_inches="tight",
            bbox_extra_artists=extra_artists,
        )
    plt.show()
    plt.close(fig)

def plot_utilization_comparison(
    rates, operators, real_data, sim_data, app, app_dir, nodes, cores, p
):
    fig, ax = plt.subplots()
    cmap = plt.get_cmap("tab20")
    colors = [cmap(i % cmap.N) for i in range(len(operators))]
    observed_max = 1.0

    for i, operator in enumerate(operators):
        for period in range(len(rates)):
            real_samples = real_data[operator][period]
            sim_samples = sim_data[operator][period]
            observed_max = max(observed_max, max(real_samples), max(sim_samples))
            real_x, real_y = period_xy(period, real_samples)
            sim_x, sim_y = period_xy(period, sim_samples)
            ax.plot(
                real_x, real_y, color=colors[i], linestyle="-",
                linewidth=2.8, alpha=1.0, zorder=3,
                marker="o" if len(real_samples) == 1 else None,
            )
            ax.plot(
                sim_x, sim_y, color=colors[i], linestyle=(0, (6, 3)),
                linewidth=2.8, alpha=0.9, zorder=4,
                marker="o" if len(sim_samples) == 1 else None,
            )

    annotations = configure_axes(
        ax, rates, observed_max, app, nodes, cores, p,
        "Dynamic Operator Utilization: Real vs Simulated",
    )
    operator_legend = position_legend_and_axes(fig, ax, operators, colors)

    style_handles = [
        Line2D([0], [0], color="black", linestyle="-", linewidth=2,
               label="Real"),
        Line2D([0], [0], color="black", linestyle="--", linewidth=2,
               label="Simulated"),
    ]
    ax.legend(handles=style_handles, loc="upper right", frameon=True)

    output_file = (
        f"metrics/{app_dir}/utilization/plot-real-sim/dynamic/"
        f"dynamic-utilization-real-sim-{app}-{nodes}-{cores}-{p}"
    )
    save_plot(fig, output_file, [operator_legend, *annotations])


def main():
    parser = argparse.ArgumentParser(
        description="Compare normalized real and simulated operator utilization"
    )
    parser.add_argument("app")
    parser.add_argument("app_dir")
    parser.add_argument("nodes")
    parser.add_argument("cores")
    parser.add_argument("p")
    args = parser.parse_args()

    real_filename = (
        f"metrics/{args.app_dir}/utilization/real/dynamic/"
        f"dynamic-utilization-real-"
        f"{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    )
    sim_filename = (
        f"metrics/{args.app_dir}/utilization/sim/dynamic/"
        f"dynamic-utilization-sim-"
        f"{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    )
    rates_real, ops_real, real_data = read_file(real_filename)
    rates_sim, ops_sim, sim_data = read_file(sim_filename)
    if rates_real != rates_sim:
        raise ValueError("Real and simulated files have different arrival rates")
    if set(ops_real) != set(ops_sim):
        raise ValueError("Real and simulated files contain different operators")

    plot_utilization_comparison(
        rates_real, ops_real, real_data, sim_data, args.app,
        args.app_dir, args.nodes, args.cores, args.p,
    )


if __name__ == "__main__":
    main()
