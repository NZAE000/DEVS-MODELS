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

            utilizations = [
                float(x)
                for x in block.split()
            ]

            operator_data[operator][rate] = utilizations

    return rates, operators, operator_data



def plot_utilization(
    rates,
    operators,
    operator_data,
    app,
    nodes,
    cores,
    p
):

    plt.figure(figsize=(14, 8))

    if len(rates) > 1:
        rate_spacing = rates[1] - rates[0]
    else:
        rate_spacing = rates[0]

    #
    # Una curva por operador
    #
    for operator in operators:

        x_values = []
        y_values = []

        for rate in rates:

            samples = operator_data[operator][rate]

            n = len(samples)

            #
            # Caso especial: sólo existe una tasa
            #
            if len(rates) == 1:

                interval_start = 0
                interval_end = rate

            else:

                interval_start = rate

                if rate == rates[-1]:
                    interval_end = rate + rate_spacing
                else:
                    interval_end = rates[rates.index(rate) + 1]

            interval_size = (
                interval_end - interval_start
            )

            if n == 1:

                x_values.append(interval_start)
                y_values.append(samples[0])

                continue

            for i, utilization in enumerate(samples):

                relative_pos = i / (n - 1)

                x = (
                    interval_start
                    + relative_pos * interval_size
                )

                x_values.append(x)
                y_values.append(utilization)

        plt.plot(
            x_values,
            y_values,
            marker="o",
            markersize=2,
            linewidth=1,
            label=operator
        )

    #
    # Separadores de tasas
    #
    for rate in rates:

        plt.axvline(
            x=rate,
            linestyle=":",
            linewidth=1,
            alpha=0.3
        )

    plt.xlabel(
        "Arrival Rate (events/s)",
        labelpad=25
    )

    plt.ylabel("Utilization")

    plt.title(
        f"Operator Utilization vs Arrival Rate\n"
        f"App={app}, Nodes={nodes}, "
        f"Cores={cores}, P={p}"
    )

    plt.grid(True)

    formatter = FuncFormatter(lambda x, pos: f"{x/1e6:.0f}M")

    ax = plt.gca()

    #
    # Mostrar sólo los ticks relevantes
    #
    if len(rates) == 1:
        ax.set_xticks([0, rates[0]])
    else:
        ax.set_xticks(rates)

    ax.xaxis.set_major_formatter(formatter)

    plt.legend(
        loc="upper center",
        bbox_to_anchor=(0.5, -0.18),
        ncol=3
    )

    plt.tight_layout()

    plt.subplots_adjust(
        bottom=0.25
    )

    output_file = (
        f"metrics/nexmark/utilization/plot-sim/dynamic/"
        f"dynamic-utilization-sim-{app}-{nodes}-{cores}-{p}.png"
    )

    plt.savefig(
        output_file,
        dpi=300,
        bbox_inches="tight"
    )

    plt.show()

    print(
        f"Graph saved in: {output_file}"
    )
    



def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("app")
    parser.add_argument("nodes", type=int)
    parser.add_argument("cores", type=int)
    parser.add_argument("p", type=int)

    args = parser.parse_args()

    filename = (
        "metrics/nexmark/utilization/simulated/dynamic/dynamic-utilization-sim-"
        f"{args.app}-{args.nodes}-{args.cores}-{args.p}.txt"
    )

    rates, operators, operator_data = read_file(filename)

    plot_utilization(
        rates,
        operators,
        operator_data,
        args.app,
        args.nodes,
        args.cores,
        args.p
    )


if __name__ == "__main__":
    main()