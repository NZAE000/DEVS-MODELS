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
    time_to_finish = None
    productor_state = None

    for line in reversed(lines): # Get from last line.
        if re.match(r"\d{2}:\d{2}:\d{2}:\d{3}:\d{3}:\d{3}:\d{3}:\d{3}", line.strip()):
            time_to_finish = line.strip()
            block.append(line.strip())
            break
        else:
            block.append(line.strip())

    block.reverse()

    for linea in block: # Detect productor state.
        if "State for model productor is" in linea:
            productor_state = int(linea.split()[-1])
            break

    # === Find the first time that state appears ===
    time_last_arrival = None
    for i in range(len(lines)):
        if f"State for model productor is {productor_state}" in lines[i]:
            time_last_arrival = lines[i-1]
            break
    
    #print("fini: ", time_to_finish, "last: ", time_last_arrival)
    time_finish = parse_time_to_sec(time_to_finish) if time_to_finish else None
    time_last_arr = parse_time_to_sec(time_last_arrival) if time_last_arrival else None

    return productor_state, time_finish, time_last_arr

def extract_rates(path):
    rates = []
    with open(path, "r") as file:
        for line in file:
            if line.strip():
                rate = line.strip().split()[-1]
                if rate not in rates:
                    rates.append(rate)
    return rates

def record_throughput(rates, reqs, time_finish, output_path):
    rates_str = ";".join(rates)
    throughput = reqs / time_finish if time_finish > 0 else 0
    line = f"{rates_str} {reqs} {time_finish:.6f} {throughput:.5f}\n"
    with open(output_path, "a") as file:
        file.write(line)
    return line.strip()



# === File paths ===
arrival_periods_path = "simulation_results/system/rate_change.txt"
states_by_time_path = "simulation_results/system/system_test_output_state.txt"
throughput_path = "throughput.txt"

# === Main execution ===

requirements_completed, time_finish, time_last_arr = extract_requirements_completed(states_by_time_path)
used_rates = extract_rates(arrival_periods_path)
line_record = record_throughput(used_rates, requirements_completed, time_finish, throughput_path)

print("\nNew record added to", throughput_path, ":")
print(line_record)

