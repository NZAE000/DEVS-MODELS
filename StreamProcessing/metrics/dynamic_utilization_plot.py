from collections import defaultdict
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter
from collections import defaultdict
import argparse
import re


plt.style.use("metrics/thesis.mplstyle")

def read_file(filename):
    with open(filename, "r") as file:
        lines = [line.strip() for line in file if line.strip()]

    if not lines:
        raise ValueError("The input file is empty.")

    # The first line contains the rates in temporal order
    rates = [int(value) for value in lines[0].split()]
    operators = []
    operator_data = defaultdict(list)

    # The remaining lines contain one utilization block per rate interval
    for line in lines[1:]:
        operator, data = line.split(":", 1)
        operator = operator.strip()
        blocks = re.findall(r"\[(.*?)\]", data)

        if len(blocks) != len(rates):
            raise ValueError(
                f"Operator '{operator}' has {len(blocks)} utilization blocks, "
                f"but {len(rates)} rate intervals were expected."
            )

        operators.append(operator)

        for block in blocks:
            utilizations = [float(value) for value in block.split()]
            operator_data[operator].append(utilizations)

    return rates, operators, operator_data


def plot_utilization(rates, operators, operator_data, app, nodes, cores, p, data_from):
    def format_rate(value):
        value = float(value)
        abs_value = abs(value)

        if abs_value >= 1_000_000:
            scaled = value / 1_000_000
            return f"{scaled:.0f}M" if scaled.is_integer() else f"{scaled:g}M"

        if abs_value >= 1_000:
            scaled = value / 1_000
            return f"{scaled:.0f}K" if scaled.is_integer() else f"{scaled:g}K"

        return f"{value:.0f}"

    if not rates:
        raise ValueError("No rate intervals were provided.")

    fig, ax = plt.subplots()
    rate_count = len(rates)

    # Plot one utilization curve per operator
    for operator in operators:
        intervals = operator_data[operator]

        if len(intervals) != rate_count:
            raise ValueError(
                f"Operator '{operator}' has {len(intervals)} utilization intervals, "
                f"but {rate_count} were expected."
            )

        x_values = []
        y_values = []

        # Use the interval index instead of the rate value
        for rate_index, samples in enumerate(intervals):
            if not samples:
                continue

            sample_count = len(samples)
            interval_start = rate_index / rate_count
            interval_end = (rate_index + 1) / rate_count
            interval_size = interval_end - interval_start

            if sample_count == 1:
                x_values.append(interval_start + interval_size / 2.0)
                y_values.append(samples[0])
                continue

            for sample_index, utilization in enumerate(samples):
                relative_position = sample_index / (sample_count - 1)
                x_values.append(interval_start + relative_position * interval_size)
                y_values.append(utilization)

        ax.plot(x_values, y_values, marker="o", label=operator)

    # Draw rate interval boundaries
    boundaries = [index / rate_count for index in range(rate_count + 1)]

    for boundary in boundaries:
        ax.axvline(x=boundary, linestyle=":", color="grey")

    ax.set_xlabel("Time Period", labelpad=40)
    ax.set_ylabel("Utilization")
    ax.set_title(
        f"Dynamic {data_from} Operator Utilization\n"
        f"App={app}, Nodes={nodes}, Cores={cores}, P={p}"
    )

    ax.set_xlim(0.0, 1.0)
    ax.set_ylim(0.0, 1.0)
    ax.set_xticks([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
    ax.set_xticklabels(["0", "0.2", "0.4", "0.6", "0.8", "1"])
    ax.grid(True)

    # Draw every rate occurrence below its corresponding interval
    for rate_index, rate in enumerate(rates):
        interval_start = rate_index / rate_count
        interval_end = (rate_index + 1) / rate_count
        center = (interval_start + interval_end) / 2.0

        ax.annotate(
            format_rate(rate),
            xy=(center, 0),
            xycoords=("data", "axes fraction"),
            xytext=(0, -25),
            textcoords="offset points",
            ha="center",
            va="top",
            color="red"
        )

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

    legend_ops = ax.legend(
        loc="upper center",
        bbox_to_anchor=(0.5, -0.18),
        ncol=min(3, len(operators))
    )

    # Reserve space for external labels and the legend
    fig.subplots_adjust(left=0.14, bottom=0.25)

    output_file = (
        f"metrics/nexmark/utilization/"
        f"plot-{data_from}/dynamic/"
        f"dynamic-utilization-{data_from}-"
        f"{app}-{nodes}-{cores}-{p}"
    )

    fig.savefig(
        f"{output_file}.pdf",
        bbox_extra_artists=(legend_ops, rate_label)
    )

    fig.savefig(
        f"{output_file}.png",
        bbox_extra_artists=(legend_ops, rate_label)
    )

    plt.show()
    
def main():

    parser = argparse.ArgumentParser(
        description="Plot operator utilizations vs Time period"
    )

    parser.add_argument("app")
    parser.add_argument("nodes", type=int)
    parser.add_argument("cores", type=int)
    parser.add_argument("p", type=int)
    parser.add_argument("data_from")
    
    args = parser.parse_args()
    
    if args.data_from != "real" and args.data_from != "sim":
        print("Data must be real or sim")

    filename = (
        f"metrics/nexmark/utilization/{f"{args.data_from}"}/dynamic/dynamic-utilization-"
        f"{args.data_from}-{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    )

    rates, operators, operator_data = read_file(filename)

    plot_utilization(
        rates,
        operators,
        operator_data,
        args.app,
        args.nodes,
        args.cores,
        args.p,
        args.data_from
    )


if __name__ == "__main__":
    main()