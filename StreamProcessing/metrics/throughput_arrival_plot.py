import matplotlib.pyplot as plt

# === Functions ===

def read_logs_throughput_arrival_rate(path):
    records = []
    with open(path, "r") as file:
        for line in file:
            if line.strip():
                parts = line.strip().split()
                rates = parts[0]
                reqs = int(parts[1])
                finish_time = float(parts[2])
                throughput = float(parts[3])
                time_last_arrival = float(parts[4])
                arrival_rate = float(parts[5])

                records.append((rates, reqs, finish_time, throughput, time_last_arrival, arrival_rate))
    return records

def show_table(records):
    print("\nThroughput - Time Arrival:")
    print(f"{'Arrival rates':<40} {'Requirements':<18} {'Finish time (s)':<20} {'Throughput (req/s)':<23} {'Time last arival (s)':<25} {'Arrival rate (req/s)':<20}")
    print("-" * 152)
    for rates, reqs, finish_time, throughput, time_last_arrival, arrival_rate in records:
        print(f"{rates:50} {reqs:<15} {finish_time:<24.6f} {throughput:<24.2f} {time_last_arrival:<25.6f} {arrival_rate:<20.2f}") 

def plot_throughput(records):
    #x_labels = [f"{time:.4f}s\n[{rates}]" for rates, time, _, _ in records]
    #y_values = [tp for _, _, _, tp in records]
#
    #plt.figure(figsize=(10, 6))
    #plt.plot(x_labels, y_values, marker="o")
    #plt.xlabel("Total time and Arrival rates")
    #plt.ylabel("Throughput (req/s)")
    #plt.title("Throughput by simulation configuration")
    #plt.grid(True)
    #plt.tight_layout()
    #plt.xticks(rotation=45)
    #plt.show()

    x_labels = []
    throughputs = []
    arrival_rates = []

    #prev_rates = None
    for rates, _, _, throughput, _, arrival_rate in records:
        label = f"[{rates}]"
        x_labels.append(label)
        throughputs.append(throughput)
        arrival_rates.append(arrival_rate)

    x = range(len(x_labels))

    plt.figure(figsize=(10, 6))
    #plt.style.use('dark_background')
    plt.plot(x, throughputs, label='Throughput', color='blue')
    plt.plot(x, arrival_rates, linestyle='--', label='Arrival Rate', color='orange')

    plt.xlabel("Rate")
    plt.ylabel("(req/s)")
    plt.title("Throughput vs Arrival Rate")
    plt.xticks(fontsize=6, ticks=x, labels=x_labels, rotation=90)
    plt.grid(True)
    plt.legend(loc='center left') # bbox_to_anchor=(1.05, 1)
    plt.tight_layout()
    plt.show()


# === File path ===
throughput_path = "metrics/throughput_result.txt"

# === Main execution ===

records = read_logs_throughput_arrival_rate(throughput_path)
show_table(records)

plot_throughput(records)


'''
def plot_throughput(records):
    #x_labels = [f"{time:.4f}s\n[{rates}]" for rates, time, _, _ in records]
    #y_values = [tp for _, _, _, tp in records]
#
    #plt.figure(figsize=(10, 6))
    #plt.plot(x_labels, y_values, marker="o")
    #plt.xlabel("Total time and Arrival rates")
    #plt.ylabel("Throughput (req/s)")
    #plt.title("Throughput by simulation configuration")
    #plt.grid(True)
    #plt.tight_layout()
    #plt.xticks(rotation=45)
    #plt.show()

    x_labels = []
    throughputs = []
    arrival_rates = []
    num_records = len(records)

    #prev_rates = None
    n = 1
    for rates, _, _, throughput, _, arrival_rate in records:
        label = n#f"[{rates}]"
        x_labels.append(label)
        throughputs.append(throughput)
        arrival_rates.append(arrival_rate)
        n += 1

    x = range(num_records)
    
    # Tick ​​positions on the X axis (each step executions).
    step = 30
    xticks_pos = list(range(0, len(records) + 1, step))

    # Label centered between each interval.
    scenario_labels_pos = [i + step // 2 for i in xticks_pos]
    scenario_labels = [f"Scenario {i+1}" for i in range(len(scenario_labels_pos)-1)]

    # Set design.
    plt.figure(figsize=(10, 6))
    #plt.style.use('dark_background')

    # Set curves.
    plt.plot(x, throughputs, label='Throughput', color='blue')
    plt.plot(x, arrival_rates, linestyle='--', label='Arrival Rate', color='orange')

    # Set Ticks.
    plt.xticks(fontsize=10, ticks=xticks_pos)#, labels=x_labels, rotation=0)

    # Assign labels between intervals.
    begin = 0
    for x_pos, label in zip(scenario_labels_pos, scenario_labels):
        throughput_interval = throughputs[begin:begin+step]
        y_pos = max(throughput_interval) * 1.05
        plt.text(x_pos, y_pos, label, color='black', fontsize=10, ha='center', va='bottom')
        begin += step

    plt.xlabel("Executions")#"Rate")
    plt.ylabel("(req/s)")
    plt.title("Throughput vs Arrival Rate")
    plt.grid(True)
    plt.legend(loc='center left') # bbox_to_anchor=(1.05, 1)
    plt.tight_layout()
    plt.show()


# === File path ===
throughput_path = "metrics/throughput_result.txt"

# === Main execution ===

records = read_logs_throughput_arrival_rate(throughput_path)
show_table(records)

plot_throughput(records)
'''