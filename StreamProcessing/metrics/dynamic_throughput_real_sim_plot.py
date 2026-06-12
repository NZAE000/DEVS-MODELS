import argparse
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


def read_file(filename):

    rate_data = {}
    rates = []

    with open(filename, "r") as f:

        for line in f:

            line = line.strip()

            if not line:
                continue

            rate_str, data = line.split(":", 1)

            rate = int(rate_str)

            rates.append(rate)

            samples = []

            for point in data.split():

                time_str, thr_str = point.split(",")

                samples.append(
                    (
                        float(time_str),
                        float(thr_str)
                    )
                )

            rate_data[rate] = samples

    return rates, rate_data


def plot_dynamic_comparison(
    rates,
    real_data,
    sim_data,
    app,
    nodes,
    cores,
    p
):

    plt.figure(figsize=(12, 7))

    ax = plt.gca()

    #
    # Curvas observadas
    #
    real_x = []
    real_y = []

    sim_x = []
    sim_y = []

    real_end_times = []
    sim_end_times = []

    for rate in rates:

        real_samples = sorted(
            real_data[rate],
            key=lambda x: x[0]
        )

        sim_samples = sorted(
            sim_data[rate],
            key=lambda x: x[0]
        )

        for t, thr in real_samples:
            real_x.append(t)
            real_y.append(thr)

        for t, thr in sim_samples:
            sim_x.append(t)
            sim_y.append(thr)

        real_end_times.append(
            real_samples[-1][0]
        )

        sim_end_times.append(
            sim_samples[-1][0]
        )

    plt.plot(
        real_x,
        real_y,
        marker="o",
        markersize=3,
        linewidth=1.5,
        label="Real"
    )

    plt.plot(
        sim_x,
        sim_y,
        marker="o",
        markersize=3,
        linewidth=1.5,
        label="Simulation"
    )

    #
    # Tiempos promedio para
    # intervalos y curva ideal
    #
    avg_end_times = []

    for tr, ts in zip(
        real_end_times,
        sim_end_times
    ):
        avg_end_times.append(
            (tr + ts) / 2.0
        )

    #
    # Curva ideal
    #
    ideal_x = [0.0]
    ideal_y = [rates[0]]

    for i in range(
        len(rates) - 1
    ):

        ideal_x.append(
            avg_end_times[i]
        )

        ideal_y.append(
            rates[i + 1]
        )

    ideal_x.append(
        avg_end_times[-1]
    )

    ideal_y.append(
        rates[-1]
    )

    plt.step(
        ideal_x,
        ideal_y,
        where="post",
        linestyle="--",
        linewidth=2,
        label="Ideal"
    )

    plt.xlabel(
        "Time (s)",
        labelpad=40
    )

    plt.ylabel(
        "Throughput (req/s)"
    )

    plt.title(
        f"Dynamic Throughput: Real vs Simulated\n"
        f"App={app}, "
        f"Nodes={nodes}, "
        f"Cores={cores}, "
        f"P={p}"
    )

    plt.grid(True)
    plt.legend()

    #
    # Separadores
    #
    plt.axvline(
        x=0,
        linestyle=":",
        linewidth=1,
        alpha=0.4
    )

    for end_time in avg_end_times:

        plt.axvline(
            x=end_time,
            linestyle=":",
            linewidth=1,
            alpha=0.4
        )

    #
    # Segunda fila:
    # Arrival Rates
    #
    interval_start = 0.0

    for rate, interval_end in zip(
        rates,
        avg_end_times
    ):

        center = (
            interval_start
            + interval_end
        ) / 2.0

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

    xticks = [0.0] + avg_end_times

    ax.set_xticks(
        xticks
    )

    ax.set_xticklabels(
        [
            f"{x:.2f}s"
            for x in xticks
        ]
    )

    formatter = FuncFormatter(
        lambda x, pos:
        f"{x/1e6:.0f}M"
    )

    ax.set_yticks(
        [0] + rates
    )

    ax.yaxis.set_major_formatter(
        formatter
    )

    plt.tight_layout()

    plt.subplots_adjust(
        bottom=0.18
    )

    output_file = (
        "metrics/nexmark/"
        "throughput/"
        "plot-real-sim/"
        "dynamic/"
        f"dynamic-throughput-"
        f"real-sim-"
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

    print(
        f"Graph saved in: "
        f"{output_file}"
    )
    
    
def main():
    
    parser = argparse.ArgumentParser(
        description="Plot throughput vs Time"
    )

    parser.add_argument("app")
    parser.add_argument("nodes")
    parser.add_argument("cores")
    parser.add_argument("p")

    args = parser.parse_args()
    
    filename_real = (
        f"metrics/nexmark/throughput/real/dynamic/dynamic-throughput-real-"
        f"{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    )

    filename_sim = (
            f"metrics/nexmark/throughput/sim/dynamic/dynamic-throughput-sim-"
            f"{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
        )
    
    rates_real, real_data = read_file(filename_real)
    rates_sim, sim_data = read_file(filename_sim)

    if rates_real != rates_sim:
        raise ValueError(
            "Real and simulation files "
            "contain different arrival rates."
        )

    plot_dynamic_comparison(
        rates_real,
        real_data,
        sim_data,
        args.app,
        args.nodes,
        args.cores,
        args.p
    )


if __name__ == "__main__":
    main()