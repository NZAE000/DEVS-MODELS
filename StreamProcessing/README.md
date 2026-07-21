# Stream Processing System (SPS) DEVS Simulator

## System Requirements

The Stream Processing simulator is developed in C++, and the logs generated at the end of the execution are processed using Bash scripts and Python. Therefore, the following requirements are necessary to perform these two general tasks:

### 1. Stream Processing Simulator in C++

#### Software Requirements:

• Operating system: Linux (Ubuntu 20.04 or later), macOS, or Windows 10 with the Cygwin subsystem or WSL.
• Compiler: g++ version 9.3 or later, or an equivalent clang++ version.
• Required standard: C++23 support.
• External dependencies: Boost.
• Build tools: GNU Make version 3.8 or later.
• Version control system: Git to clone the Cadmium (2020) repository and the stream processing model.

#### Recommended Hardware Requirements:

• Multicore processor (minimum 4 cores).
• RAM: at least 4 GB.
• Disk space: 2 GB available to store simulation logs.

### 2. Result Processing and Analysis in Python

#### Software Requirements:

• Python 3.13 or later.
• Required libraries:
◦ re (regular expression matching)
◦ collections (specialized containers)
◦ matplotlib (visualization)
• Recommended virtual environment: venv or conda for dependency management.

#### Recommended Hardware Requirements:

• Standard compatible CPU, using the same environment as the simulator.
• RAM: minimum 4 GB.
• Disk space: at least 500 MB for calculated metric files.

## Environment Setup

### 1. Windows with Cygwin

1. Download and install Cygwin from https://www.cygwin.com/.
2. During installation, make sure to include the required development packages (`gcc-core`, `gcc-g++`, `make`, `cmake`, `libboost-devel`, `python3`, `python3-pip`, and `git`).

### 2. Windows Using WSL

1. Enable Windows Subsystem for Linux (WSL):

   * Open PowerShell as administrator.
   * Run the command: `wsl --install`
   * Restart the computer if necessary.
2. Install a Linux distribution, such as Ubuntu 20.04, from the Microsoft Store.
3. Open the Ubuntu terminal and update the packages:

```bash
$ sudo apt update && sudo apt upgrade -y
```

4. Install the required C++ tools:

```bash
$ sudo apt install build-essential g++ cmake make -y
$ sudo apt install libboost-all-dev -y
```

5. Install Python:

```bash
$ sudo apt install python3 python3-pip python3-venv -y
```

6. Install Git:

```bash
$ sudo apt install git -y
```

### 3. Linux

1. Update the system:

```bash
$ sudo apt update && sudo apt upgrade -y
```

2. Install the C++ tools:

```bash
$ sudo apt install build-essential g++ cmake make -y
$ sudo apt install libboost-all-dev -y
```

3. Install Python and Git:

```bash
$ sudo apt install python3 python3-pip python3-venv -y
$ sudo apt install git -y
```

### 4. macOS

1. Install Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. Install the required tools:

```bash
$ brew install gcc cmake make boost python
```

4. Install Git:

```bash
$ brew install git
```

Once the requirements are ready, the **Cadmium** library must be installed to build the DEVS-based model. Detailed instructions are available in its [documentation](https://cell-devs.sce.carleton.ca/index.php/cadmium/).

Then, clone this repository into the same path where Cadmium was installed:

```bash
$ git clone https://github.com/NZAE000/DEVS-MODELS.git
```

To use the Python scripts, a virtual environment must be created and activated to install the dependencies locally.

To do this, navigate to the `StreamProcessing/` directory:

```bash
$ cd StreamProcessing/
```

Then, create the Python environment:

```bash
$ python3 -m venv .venv
```

Activate the environment:

```bash
$ source .venv/bin/activate
```

Install the dependencies:

```bash
$ pip install --upgrade pip
$ pip install -r py-requirements.txt
```

Verify the installation:

```bash
$ pip list
```

When you finish using the scripts, deactivate the environment:

```bash
$ deactivate
```

To automate the environment installation, run the following script from the `StreamProcessing/` directory:

```bash
$ bash setup_python_env.sh
```

## Documentation

### Repository Structure

* `atomics/`: Contains the header files that define the atomic components of the model, such as `producer.hpp` and `node.hpp`.
* `bin/`: Contains all executable binaries, including the `STREAM_PROCESSING` simulator.
* `build/`: Contains all compiled intermediate binaries, which are linked to generate the executable binary in `bin/`.
* `data_structures/`: Contains the code for the data structures designed by the developer to divide the model behavior into concepts and responsibilities that complement the atomic models. For example, it includes the structures that define the message types used by the communication ports between atomic and coupled components, as well as the structures of the Flink architecture components and their functions.
* `distribution_test/`: Includes source files used to test different random distribution functions, such as normal and exponential distributions, to inspect random values generated with specific arguments before using them in the simulation.
* `input_data/`: Includes the files used to configure the simulation parameters, such as `arrivalrates.txt`, `workload.txt`, `hardware.hpp`, `operator.txt`, and `topology.txt`.
* `metrics/`: Stores metrics from scenarios executed in real and simulated applications. It also contains Python scripts for processing these metrics, exporting them to CSV files, and graphically displaying new evaluation metrics.
* `simulation_result/`: Currently unused. It stores files containing message and state logs from the atomic models used in unit, integration, and system tests through the default Cadmium loggers described in the manual. **IMPORTANT:** Reading these logs previously allowed metrics to be calculated and obtained. However, the Cadmium loggers were disabled because the SPS model is configured with high-workload scenarios, resulting in execution times of several hours due to the extremely high frequency of disk writes generated by these loggers.
* `test/`: Contains the main source code for unit, integration, and system tests. The model, or parts of the model, is built in these main source files according to the test type by instantiating atomic components, coupled-model ports, model couplings, the top-level model, loggers, and the simulation execution call.
* `util/`: Contains required utility code, such as random distribution functions.
* `makefile`: File used to compile and build the simulator. Its main purpose is to manage dependencies and simplify the compilation process.
* `run_simulation.sh`: Script used to automate the simulation cleaning, compilation, and execution processes.

## User Manual

As a functional requirement, the simulator reads the files located in the `input_data` directory, which contain the parameters defined by the user to configure the model. The user then compiles and runs the simulator.

### Configuration Files

* `workload.txt`: Configures the workload. It specifies the number of requests to be sent and the arrival rate. For example: `100000000 1e-05`.
* `arrivalrates.txt`: Optional alternative to `workload.txt`. It defines arrival-rate changes and the time at which each change must occur so that the producer model can simulate variations in the arrival of events to the system. Note: the first timestamp must begin at `0`, and the final value of `λ` must be zero to indicate the end of event generation.
* `hardware.hpp`: Assigns the number of machines and the number of homogeneous cores in the cluster model through the `N_NODES` and `N_CORES` macros, respectively. Note: whenever a different value is assigned, the model must be recompiled as shown below.
* `hardware.txt`: Under development for future hardware definitions.
* `operator.txt`: Defines the properties of the operators that make up the simulated application. Each property must follow the format `id replica distribution args exchange selectivity`.
* `topology.txt`: Defines the topology of the application to be simulated using the same operator names defined in the `operator.txt` file. It follows the format `from to`.
* `degradation.txt`: Contains factors used to model performance degradation effects, particularly at high parallelism levels in a simulated application.
* `extraoccupation.txt`: Contains factors used to model the additional internal occupancy of operators, particularly at high parallelism levels in a simulated application.

### Execution

From the root directory of the StreamProcessing model:

```bash
$ make make STREAM_PROCESSING N_NODES=n_nodes N_CORES=n_cores PARALLELISM_L=p_level PROD_MOD=prod_mod APPLY_LOG=apply_log LOG_MOD=log_mod PRINT_LOG=print_log -j
```

where:

* `N_NODES`: Number of machines.
* `N_CORES`: Number of cores per machine.
* `PARALLELISM_L`: Application parallelism level. When `PARALLELISM_L > 1`, all operators are parallelized using the same level. Otherwise, the values defined in the `operator.txt` configuration file are used.
* `PROD_MOD`: A value of `1` uses the `arrivalrates.txt` file to produce events using one or more arrival rates at configured points in time. A value of `0` uses the `workload.txt` file to apply a single workload throughout the entire simulation.
* `APPLY_LOG`: A value of `1` records metrics in the `metrics/` directory. A value of `0` disables metric logging.
* `LOG_MOD`: A value of `1` records metrics throughout the entire simulation. A value of `0` records only the accumulated metrics at the end of the simulation.
* `PRINT_LOG`: A value of `1` prints all metric logs at the end of the execution. A value of `0` does not print them.

To clean and recompile:

```bash
$ make clean && make make STREAM_PROCESSING N_NODES=n_nodes N_CORES=n_cores PARALLELISM_L=p_level PROD_MOD=prod_mod APPLY_LOG=apply_log LOG_MOD=log_mod PRINT_LOG=print_log -j
```

Run:

```bash
$ ./bin/STREAM_PROCESSING <app_name>
```

Automated execution, including cleaning, compilation, and execution:

```bash
$ bash run_simulation.sh <app_name> <nodes> <cores> <p_level> <prod_mod> <n_exec> <apply_log> <log_mod> <print_log>"
```

### Running Experiments

Under development.

### Metric Visualization

Under development.

---

> **Note:** For more information, refer to the complete model documentation or contact the author.
