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
    plt.plot(x, throughputs, marker='o', label='Throughput (req/s)', color='blue')
    plt.plot(x, arrival_rates, marker='s', linestyle='--', label='Arrival Rate (req/s)', color='orange')

    plt.xlabel("Rate")
    plt.ylabel("(req/s)")
    plt.title("Throughput vs Arrival Rate")
    plt.xticks(fontsize=6, ticks=x, labels=x_labels, rotation=90)
    plt.grid(True)
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()
    plt.show()


# === File path ===
throughput_path = "throughput.txt"

# === Main execution ===

records = read_logs_throughput_arrival_rate(throughput_path)
show_table(records)

plot_throughput(records)

