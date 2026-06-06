from collections import defaultdict
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter
from collections import defaultdict
import argparse
import re




def read_file(filename):

    with open(filename, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    #
    # Primera línea: rates
    #
    rates = [int(x) for x in lines[0].split()]
    operators = []
    operator_data = defaultdict(dict)

    #
    # Resto de líneas: operadores
    #
    for line in lines[1:]:

        operator, data = line.split(":", 1)
        operators.append(operator)

        #
        # Extraer todos los bloques [...]
        #
        blocks = re.findall(r"\[(.*?)\]", data)
        for rate, block in zip(rates, blocks):

            utilizations = [float(x) for x in block.split()]
            operator_data[operator][rate] = utilizations

    return rates, operators, operator_data



def plot_utilization(rates, operators, operator_data, app, nodes, cores, p, data_from):

    plt.figure(figsize=(14, 8))
    ax = plt.gca()

    #
    # Curva de cada operador
    #
    for operator in operators:

        x_values = []
        y_values = []
        interval_start = 0.0

        for idx, rate in enumerate(rates):

            samples = operator_data[operator][rate]
            n = len(samples)

            #
            # Intervalo normalizado
            #
            if len(rates) == 1:
                interval_end = 1.0
            else:
                interval_end = (idx + 1) / len(rates)

            interval_size = (interval_end - interval_start)

            if n == 1:
                x_values.append(interval_start + interval_size / 2.0)
                y_values.append(samples[0])

            else:

                for i, utilization in enumerate(samples):

                    relative_pos = (i / (n - 1))
                    x = (interval_start + relative_pos * interval_size)
                    x_values.append(x)
                    y_values.append(utilization)

            interval_start = interval_end

        plt.plot(
            x_values,
            y_values,
            marker="o",
            markersize=2,
            linewidth=1,
            label=operator
        )

    #
    # Líneas divisorias entre tasas
    #
    plt.axvline(
        x=0,
        linestyle=":",
        linewidth=1,
        alpha=0.3
    )

    if len(rates) == 1:
        boundaries = [1.0]
    else:
        boundaries = [(i + 1) / len(rates) for i in range(len(rates))]

    for boundary in boundaries:
        plt.axvline(
            x=boundary,
            linestyle=":",
            linewidth=1,
            alpha=0.3
        )

    plt.xlabel(
        "Time Period",
        labelpad=40
    )

    plt.ylabel("Utilization")

    plt.title(
        f"Operator Utilization vs Time\n"
        f"App={app}, Nodes={nodes}, "
        f"Cores={cores}, P={p}"
    )

    plt.grid(True)

    #
    # Eje X
    #
    xticks = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
    ax.set_xticks(xticks)
    ax.set_xticklabels(["0", "0.2", "0.4", "0.6", "0.8", "1"])

    #
    # Segunda fila: Arrival Rates
    #
    interval_start = 0.0

    for idx, rate in enumerate(rates):

        if len(rates) == 1:
            interval_end = 1.0
        else:
            interval_end = (idx + 1) / len(rates)

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

    plt.legend(
        loc="upper center",
        bbox_to_anchor=(0.5, -0.18),
        ncol=3
    )

    plt.tight_layout()
    plt.subplots_adjust(bottom=0.25)

    output_file = (
        f"metrics/nexmark/utilization/"
        f"plot-{data_from}/dynamic/"
        f"dynamic-utilization-"
        f"{data_from}-"
        f"{app}-"
        f"{nodes}-"
        f"{cores}-"
        f"{p}.png"
    )

    plt.savefig(output_file, dpi=300, bbox_inches="tight")
    plt.show()
    print(f"Graph saved in: "f"{output_file}")

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