# DEVS-based Models

Repository with models implemented using Discrete Event Specification (DEVS) formalism, through the Cadmium DEVS engine, whose installation can be found in the user guide: https://cell-devs.sce.carleton.ca/index.php/cadmium/.
Anyway, don't worry, the repository already integrates the Cadmium.

This project is licensed under the MIT License. See LICENSE.

Third-Party Software.
This project includes the Cadmium DEVS engine.
Cadmium is distributed under the BSD-2-Clause License.
Copyright (c) 2013-2015 Damian Vicino,
Carleton University, Universite de Nice-Sophia Antipolis.
The full license text is available in: cadmium/BSD-LICENSE.txt

Each model directory contains its own `README.md` with the specific manual and execution instructions.

## Current Models

* `Stream Processing System (SPS)` — A DEVS-based model for simulating data flow processing systems, using Apache Flink as a case study. It is validated using Nexmark Benchmark queries and the Yahoo Streaming application.