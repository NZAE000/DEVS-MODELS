# throughput_arrival_statistics.py
import statistics

def read_throughput_arrival_data(path):
    throughputs = []
    arrival_rates = []

    with open(path, "r") as file:
        for line in file:
            if line.strip():
                parts = line.strip().split()
                if len(parts) >= 6:
                    try:
                        throughput = float(parts[3])
                        arrival_rate = float(parts[5])
                        throughputs.append(throughput)
                        arrival_rates.append(arrival_rate)
                    except ValueError:
                        continue  # Ignora líneas con valores no numéricos

    return throughputs, arrival_rates

def print_statistics(values, label):
    if not values:
        print(f"No data available for {label}")
        return

    mean_val = statistics.mean(values)
    stdev_val = statistics.stdev(values) if len(values) > 1 else 0.0

    print(f"\n{label} Statistics:")
    print(f"    AVG: {mean_val:.4f}")
    print(f"    STD: {stdev_val:.4f}")

# === File path ===
throughput_path = "metrics/throughput_result.txt"

# === Main execution ===
throughputs, arrival_rates = read_throughput_arrival_data(throughput_path)

print_statistics(throughputs, "Throughput (req/s)")
print_statistics(arrival_rates, "Arrival Rate (req/s)")
