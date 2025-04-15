import matplotlib.pyplot as plt

# === Functions ===

def read_logs_throughput(path):
    records = []
    with open(path, "r") as file:
        for line in file:
            if line.strip():
                parts = line.strip().split()
                rates = parts[0]
                reqs = int(parts[1])
                time = float(parts[2])
                throughput = float(parts[3])
                records.append((rates, time, reqs, throughput))
    return records

def show_table(records):
    print("\nThroughput Table:")
    print(f"{'Arrival rates':<30} {'time (s)':<12} {'Requirements':<16} {'Throughput (req/s)':<20}")
    print("-" * 80)
    for rates, time, reqs, throughput in records:
        print(f"{rates:<30} {time:<12.6f} {reqs:<16} {throughput:<20.2f}")

def plot_throughput(records):
    x_labels = [f"{time:.4f}s\n[{rates}]" for rates, time, _, _ in records]
    y_values = [tp for _, _, _, tp in records]

    plt.figure(figsize=(10, 6))
    plt.plot(x_labels, y_values, marker="o")
    plt.xlabel("Total time and Arrival rates")
    plt.ylabel("Throughput (req/s)")
    plt.title("Throughput by simulation configuration")
    plt.grid(True)
    plt.tight_layout()
    plt.xticks(rotation=45)
    plt.show()


# === File path ===
throughput_path = "throughput.txt"

# === Main execution ===

records = read_logs_throughput(throughput_path)
show_table(records)

plot_throughput(records)

