SIMULATOR := STREAM_PROCESSING
N_NODES := 0
CC=clang++
ifneq ($(N_NODES),0)
	CC += -DN_NODES=$(N_NODES)
endif
CFLAGS=-std=c++20 #-g #-Wall -Wextra -Wpedantic -Wconvertions

INCLUDECADMIUM=-I ../../Cadmium-Simulation-Environment/cadmium/include/ -I /opt/homebrew/Cellar/boost/1.88.0/include
INCLUDEDESTIMES=-I ../../Cadmium-Simulation-Environment/DESTimes/include/

#CREATE BIN AND BUILD FOLDERS TO SAVE THE COMPILED FILES DURING RUNTIME
bin_folder := $(shell mkdir -p bin)
build_folder := $(shell mkdir -p build)
results_folder := $(shell mkdir -p simulation_results simulation_results/unitary simulation_results/integration simulation_results/system)

#TARGET TO COMPILE ALL THE TESTS TOGETHER (NOT SIMULATOR)

# UTILS
random.o: util/random.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) util/random.cpp -o build/random.o

# DATA STRUCTURES
operator_location.o : data_structures/operator_location.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) data_structures/operator_location.cpp -o build/operator_location.o

message.o : data_structures/message.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) data_structures/message.cpp -o build/message.o

jobmanager.o : data_structures/flink/jobmanager.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) data_structures/flink/jobmanager.cpp -o build/jobmanager.o

resourcemanager.o : data_structures/flink/resourcemanager.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) data_structures/flink/resourcemanager.cpp -o build/resourcemanager.o

jobmaster.o : data_structures/flink/jobmaster.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) data_structures/flink/jobmaster.cpp -o build/jobmaster.o

taskmanager.o : data_structures/flink/taskmanager.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) data_structures/flink/taskmanager.cpp -o build/taskmanager.o

flinklib: jobmanager.o resourcemanager.o jobmaster.o taskmanager.o
	ar -crs build/libflink.a  build/jobmanager.o build/resourcemanager.o build/jobmaster.o build/taskmanager.o
	ranlib build/libflink.a


# UNITARY TESTS
main_producer_test.o : test/unitary/main_producer_test.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) test/unitary/main_producer_test.cpp -o build/main_producer_test.o

main_nodemaster_test.o : test/unitary/main_nodemaster_test.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) test/unitary/main_nodemaster_test.cpp -o build/main_nodemaster_test.o

main_switch_test.o : test/unitary/main_switch_test.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) test/unitary/main_switch_test.cpp -o build/main_switch_test.o


# INTEGRATION TESTS
main_prod_nmaster_test.o: test/integration/main_prod_nmaster_test.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) test/integration/main_prod_nmaster_test.cpp -o build/main_prod_nmaster_test.o


# SIMULATOR
main_top.o: top_model/main.cpp
	$(CC) $(CFLAGS) -c $(INCLUDECADMIUM) $(INCLUDEDESTIMES) top_model/main.cpp -o build/main_top.o

unitary_producer: main_producer_test.o operator_location.o message.o random.o flinklib
	$(CC) -o bin/PRODUCTOR_TEST build/libflink.a build/main_producer_test.o build/random.o build/operator_location.o build/message.o

unitary_nodemaster: main_nodemaster_test.o operator_location.o message.o random.o flinklib
	$(CC) -o bin/NODEMASTER_TEST build/libflink.a build/main_nodemaster_test.o build/random.o build/operator_location.o build/message.o

unitary_switch: main_switch_test.o operator_location.o message.o random.o flinklib
	$(CC) -o bin/SWITCH_TEST build/libflink.a build/main_switch_test.o build/random.o build/operator_location.o build/message.o

unitary_tests: main_producer_test.o main_nodemaster_test.o main_switch_test.o operator_location.o message.o random.o flinklib
	$(unitary_producer)
	$(unitary_nodemaster)
	$(unitary_switch)

integration_tests: main_prod_nmaster_test.o random.o operator_location.o message.o flinklib
	$(CC) -o bin/PRODUCTOR_NMASTER_TEST build/libflink.a build/main_prod_nmaster_test.o build/random.o build/operator_location.o build/message.o

#TARGET TO COMPILE ONLY STREAN PROCESSING SIMULATOR
$(SIMULATOR): main_top.o random.o operator_location.o message.o flinklib
	$(CC) -o bin/$(SIMULATOR) build/libflink.a build/main_top.o build/random.o build/operator_location.o build/message.o
	
#TARGET TO COMPILE EVERYTHING (ABP SIMULATOR + TESTS TOGETHER)
all: $(SIMULATOR) unitary_tests integration_tests

#CLEAN COMMANDS
clean: 
	rm -f bin/* build/*