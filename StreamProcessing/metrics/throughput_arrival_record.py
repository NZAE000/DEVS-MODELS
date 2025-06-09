import re
import matplotlib.pyplot as plt

# === Functions ===

def parse_time_to_sec(time_str):
    h, m, s, ms, us, ns, ps, fs = map(int, time_str.strip().split(':'))
    return (
        h * 3600 +
        m * 60 +
        s +
        ms * 1e-3 +
        us * 1e-6 +
        ns * 1e-9 +
        ps * 1e-12 +
        fs * 1e-15
    )

def extract_requirements_completed(state_file):
    with open(state_file, 'r') as file:
        lines = file.readlines()

    block = []
    final_time = None
    req_completed = None

    for line in reversed(lines): # Get from last line.
        if re.match(r"\d{2}:\d{2}:\d{2}:\d{3}:\d{3}:\d{3}:\d{3}:\d{3}", line.strip()):
            final_time = line.strip()
            block.append(line.strip())
            break
        else:
            block.append(line.strip())

    block.reverse()

    for linea in block: # Detect productor state.
        if "State for model productor is" in linea:
            req_completed = int(linea.split()[-1])
            break

    # === Find the first time that state appears ===
    time_last_arrival = None
    for i in range(len(lines)):
        if f"State for model productor is {req_completed}" in lines[i]:
            time_last_arrival = lines[i-1]
            break
    
    #print("fini: ", final_time, "last: ", time_last_arrival)
    finish_time = parse_time_to_sec(final_time) if final_time else None
    time_last_arr = parse_time_to_sec(time_last_arrival) if time_last_arrival else None

    return req_completed, finish_time, time_last_arr

def extract_rates(path):
    rates = []
    with open(path, "r") as file:
        for line in file:
            if line.strip():
                rate = line.strip().split()[-1]
                if rate not in rates:
                    rates.append(rate)
    return rates

def record_throughput(rates, reqs, finish_time, time_last_arrival, output_path):
    rates_str = ";".join(rates)
    throughput = reqs / finish_time if finish_time > 0 else 0
    arrival_rate = reqs / time_last_arrival if time_last_arrival > 0 else 0
    line = f"{rates_str} {reqs} {finish_time:.6f} {throughput:.5f} {time_last_arrival:.6f} {arrival_rate:.5f} \n" 
    with open(output_path, "a") as file:
        file.write(line)
    return line.strip()



# === File paths ===
arrival_periods_path = "simulation_results/system/rate_change.txt"
states_by_time_path = "simulation_results/system/system_test_output_state.txt"
throughput_path = "metrics/throughput_result.txt"

# === Main execution ===
requirements_completed, finish_time, time_last_arr = extract_requirements_completed(states_by_time_path)
used_rates = extract_rates(arrival_periods_path)
line_record = record_throughput(used_rates, requirements_completed, finish_time, time_last_arr, throughput_path)

print("New record added to", throughput_path, ":")
print(line_record)

