#import matplotlib.pyplot as plt
#import numpy as np
#
## === Data: Arrival Rate and Average Throughput for each scenario ===
#arrival_rates = [11162, 11259, 11297, 11113, 11206]
#throughputs   = [1973,  5163,  7078,  8215, 10865]
#escenarios    = [f"{i+1}" for i in range(5)]
#
## === Bar chart settings ===
#x = np.arange(len(escenarios))  # Positions on the X axis
#width = 0.35                    # Width of the bars
#
#plt.figure(figsize=(10, 6))
#plt.bar(x - width/2, arrival_rates, width, label='Arrival Rate (req/s)', color='orange')
#plt.bar(x + width/2, throughputs, width, label='Throughput (req/s)', color='blue')
#
#plt.xlabel('Scenarios')
#plt.ylabel('Average (req/s)')
#plt.title('Arrival Rate vs Throughput')
#plt.xticks(x, escenarios)
#plt.legend()
#plt.grid(axis='y', linestyle='--', alpha=0.6)
#plt.tight_layout()
#plt.show()

import matplotlib.pyplot as plt

# === Datos por escenario ===
arrival_rates = [11162, 11259, 11297, 11113, 11206]
throughputs   = [1973,  5163,  7078,  8215, 10865]
num_escenarios = len(arrival_rates)

# === Graficar cada escenario por separado ===
for i in range(num_escenarios):
    escenario = f"Scenario {i+1}"
    values = [arrival_rates[i], throughputs[i]]
    labels = ['Arrival Rate', 'Throughput']
    colors = ['orange', 'blue']

    plt.figure(figsize=(5, 4))
    plt.bar(labels, values, color=colors)
    plt.title(f"{escenario}")
    plt.ylabel("Average (req/s)")
    plt.ylim(0, max(arrival_rates + throughputs) * 1.1)  # margen superior
    plt.grid(axis='y', linestyle='--', alpha=0.6)
    plt.tight_layout()
    plt.show()
