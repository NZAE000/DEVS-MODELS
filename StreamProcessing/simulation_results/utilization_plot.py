from collections import defaultdict
import matplotlib.pyplot as plt
import re

# Change time format to number.
def timestamp_to_microseconds(ts):
    h, m, s, ms, us, *_ = map(int, ts.split(":"))
    return (
        h * 3600 * 10**6 + # 1hr  = 3600seg, to micro = 3600 * 10**6
        m * 60 * 10**6 +   # 1min = 60seg, to micro = 60 * 10**6
        s * 10**6 +        # 1seg to micro = 1 * 10**6
        ms * 1000 +        # 1mil to micro = 1 * 1000
        us
    )

def load_operators(file_path):
    operator_replicas = {}

    with open(file_path, 'r') as file:
        for line in file:
            line = line.strip()
            # Ignore empty lines or comments.
            if not line or line.startswith("#"):
                continue
            # Parsear replicas.
            parts = line.split()
            operator_name = parts[0]
            replicas = int(parts[1])

            # Store the operator and its number of replicas.
            operator_replicas[operator_name] = replicas

    return operator_replicas


def load_arrival_rates(file_path):
    periods = []
    with open(file_path, 'r') as file:
        lines = file.readlines()

    for i in range(len(lines)):
        ts, rate = lines[i].strip().split()
        start_time = timestamp_to_microseconds(ts)
        rate = float(rate)
        if i + 1 < len(lines):
            next_ts, _ = lines[i + 1].strip().split()
            end_time = timestamp_to_microseconds(next_ts)
        else:
            end_time = None  # Last period extends to the end of the log.
        periods.append([rate, start_time, end_time])

    return periods


def load_states_log(file_path):
    states_by_time = {}
    current_time = None

    with open(file_path, 'r') as file:
        for line in file:
            line = line.strip()
            # Detect time line.
            if re.match(r"\d{2}:\d{2}:\d{2}:\d{3}:\d{3}:\d{3}:\d{3}:\d{3}", line):
                current_time = timestamp_to_microseconds(line)
                states_by_time[current_time] = {'nodes': {}}
            
            # Detect node state.
            elif line.startswith("State for model node_"):
                node_match = re.match(r"State for model (\w+) is processing: (\d), buffer executions: \d+, (.+)", line)
                if node_match:
                    node_name, is_processing, slots_str = node_match.groups()
                    is_processing = int(is_processing)
                    slots = {}
                    
                    slot_matches = re.findall(r"\[(slot_\d+)->(\w+): running: (\d), active: (\d), tuples: \d+\]", slots_str)
                    for slot_id, operator, running, active in slot_matches:
                        slots[slot_id] = {'operator': operator, 'running': int(running)}

                    states_by_time[current_time]['nodes'][node_name] = {
                        'processing': is_processing,
                        'slots': slots
                    }
    return states_by_time


def compute_utilization(states_by_time, arrival_periods, operator_replicas):
    # Result structures.
    node_util_by_rate = []#defaultdict(dict)
    operator_util_by_rate = []#defaultdict(dict)

    sorted_times = sorted(states_by_time.keys())
    
    last_1 = len(arrival_periods)-1
    last_2 = len(arrival_periods[last_1])-1
    arrival_periods[last_1][last_2] = sorted_times[len(sorted_times)-1] # Replace None value to last time.

    #for rate, start, end in arrival_periods:
    #    print(f"Rate {rate} desde {start} hasta {end}")

    for i in range(len(arrival_periods)):
        rate, t_start, t_end = arrival_periods[i]
        interval_duration = t_end - t_start

        # Initialize usage level counters.
        node_usage_time = defaultdict(int)
        operator_running_time = defaultdict(int)

        # Set operators and order
        for operator in operator_replicas.keys():
            operator_running_time[operator] = 0

        # Iterate over pairs of times within the interval.
        relevant_times = [t for t in sorted_times if t_start <= t <= t_end]
        #print("rel_times: ", relevant_times)
        for j in range(len(relevant_times) - 1):
            t_curr = relevant_times[j]
            t_next = relevant_times[j + 1]
            delta = t_next - t_curr
            #print("curr: ", t_curr, "next: ", t_next, "delta: ", delta)

            if t_curr not in states_by_time:
                continue

            nodes = states_by_time[t_curr]['nodes']
            for node, info in nodes.items():
                # Node in use
                if info['processing'] == 1:
                    node_usage_time[node] += delta
                else:
                    node_usage_time[node] += 0

                # Active slots → operators in use.
                oper_source = False
                for slot_id, slot_info in info['slots'].items():
                    op_name = slot_info['operator']
                    if slot_info['running'] == 1:
                        if (op_name == "source"):
                            print("source-",slot_id, ": t_curr", t_curr, ", t_next: ", t_next, ", delta: ", delta)
                            oper_source = True
                        operator_running_time[op_name] += delta
                    else:
                        operator_running_time[op_name] += 0
                if (oper_source == True):
                    print("")

        #print("current rate:", rate)
        # Calculate node utilization.
        dictio1 = {}
        for node, usage in node_usage_time.items():
            #node_util_by_rate[rate][node] = usage / interval_duration
            dictio1[node] = usage / interval_duration
        node_util_by_rate.append((rate, dictio1))

        # Calculate operator usage.
        dictio2 = {}
        for op, usage in operator_running_time.items():
            ro = operator_replicas.get(op, 1)
            #operator_util_by_rate[rate][op] = (usage / ro) / interval_duration
            dictio2[op] = (usage / ro) / interval_duration
        operator_util_by_rate.append((rate, dictio2))

    #print("OPERTORS BY RATE: ", operator_util_by_rate)
    #print("NODES BY RATE: ", node_util_by_rate)
    return node_util_by_rate, operator_util_by_rate


#def display_results(node_util_by_rate, operator_util_by_rate):
#    print("Nivel de utilización de nodos:\n")
#    print("Rate\t" + "\t".join(sorted(next(iter(node_util_by_rate.values())).keys())))
#    for rate, nodes in node_util_by_rate.items():
#        print(f"{rate}\t" + "\t".join([f"{nodes[node]:.2f}" for node in sorted(nodes)]))
#
#    print("\nNivel de utilización de operadores:\n")
#    print("Rate\t" + "\t".join(sorted(next(iter(operator_util_by_rate.values())).keys()))) 
#    for rate, operators in operator_util_by_rate.items():
#        print(f"{rate}\t" + "\t".join([f"{operators[op]:.2f}" for op in sorted(operators)]))
def show_table(node_util_by_rate, operator_util_by_rate):
    print("Node utilization level:\n")
    # Obtener el primer diccionario de la primera tasa de llegada
    node_keys = node_util_by_rate[0][1].keys()
    print("Rate\t" + "\t".join(node_keys))
    
    for rate, nodes in node_util_by_rate:
        print(f"{rate}\t" + "\t".join([f"{nodes[node]:.2f}" for node in node_keys]))

    print("\nOperator utilization level:\n")
    # Obtener las claves de los operadores de la primera tasa de llegada
    operator_keys = operator_util_by_rate[0][1].keys()
    print("Rate\t" + "\t".join(operator_keys))
    
    for rate, operators in operator_util_by_rate:
        print(f"{rate}\t" + "\t".join([f"{operators[op]:.2f}" for op in operator_keys]))



#def plot_utilization_by_entity(util_by_rate, arrival_periods, title, ylabel, entity_label):
#    plt.figure(figsize=(10, 6))
#
#    rates = [rate for rate, _, _ in arrival_periods]  # Extract only the rates.
#
#    # Get all rates and all entity keys (nodes or operators)
#    all_entities = set()
#    for rate in rates:
#        all_entities.update(util_by_rate[rate].keys())
#    #print(all_entities)
#
#    rates_labels = [str(rate) for rate in rates] # To category.
#
#    # For each entity, build the list of uses along the rates.
#    for entity in all_entities:
#        #print(entity)
#        utilizations = [util_by_rate[rate].get(entity, 0.0) for rate in rates]
#        #print(utilizations)
#        plt.plot(rates_labels, utilizations, marker='o', label=f"{entity_label} {entity}")
#
#    plt.title(title)
#    plt.xlabel("Arrival Rate")
#    plt.ylabel(ylabel)
#    plt.ylim(0, 1.05)
#    plt.legend(title=entity_label, bbox_to_anchor=(1.05, 1), loc='upper left')
#    plt.grid(True)
#    plt.tight_layout()
#    #plt.show()


def plot_utilization_by_entity(util_by_rate, arrival_periods, title, ylabel, entity_label):
    plt.figure(figsize=(10, 6))

    rates = [rate for rate, _, _ in arrival_periods]   # Extract only the rates.
    x_rate_indices = list(range(len(arrival_periods)))
    x_rate_labels = [str(rate) for rate in rates]  # Tags for arrival rates (to categorize on X axis).

    # Get all entities from first arrival rates (all have the sames).
    all_entities = [entity for entity in util_by_rate[0][1].keys()]
    #all_entities.update(util_by_rate[0][1].keys())
    #for rate, entities in util_by_rate:
    #    all_entities.update(entities.keys())

    # For each entity, build the list of uses along the rates.
    for entity in all_entities:
        utilizations = [
            entities.get(entity, 0.0) for _, entities in util_by_rate
        ]
        plt.plot(x_rate_indices, utilizations, marker='o', label=f"{entity_label} {entity}")

    plt.title(title)
    plt.xlabel("Arrival Rate")
    plt.ylabel(ylabel)
    plt.ylim(0, 1.05)
    plt.xticks(x_rate_indices, x_rate_labels, rotation=45)
    plt.legend(title=entity_label, bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.grid(True)
    plt.tight_layout()
    #plt.show()


arrival_periods = load_arrival_rates("simulation_results/system/rate_change.txt")
states_by_time = load_states_log("simulation_results/system/system_test_output_state.txt")
operator_replicas = load_operators("input_data/operator.txt")
node_util_by_rate, operator_util_by_rate = compute_utilization(states_by_time, arrival_periods, operator_replicas)

#for rate, start, end in arrival_periods:
#    print(f"Rate {rate} desde {start} hasta {end}")

#for t, state in list(states_by_time.items())[:]:  # Muestra los primeros 3 tiempos
#    print(f"{t}:")
#    for node, info in state['nodes'].items():
#        print(f"  {node} - processing: {info['processing']}, slots: {info['slots']}")
#print(operator_replicas)
#print(node_util_by_rate)
#print()
#print(operator_util_by_rate)
show_table(node_util_by_rate, operator_util_by_rate)

# Graph node utilization.
plot_utilization_by_entity(
    util_by_rate=node_util_by_rate,
    arrival_periods=arrival_periods,
    title="Using Nodes",
    ylabel="Utilization",
    entity_label=""
)

# Graph operator usage.
plot_utilization_by_entity(
    util_by_rate=operator_util_by_rate,
    arrival_periods=arrival_periods,
    title="Using Operators",
    ylabel="Utilization",
    entity_label=""
)
plt.show()