//Cadmium Simulator headers
#include <cadmium/modeling/ports.hpp>
#include <cadmium/modeling/dynamic_model.hpp>
#include <cadmium/modeling/dynamic_model_translator.hpp>
#include <cadmium/engine/pdevs_dynamic_runner.hpp>
#include <cadmium/logger/common_loggers.hpp>
#include <fstream>

//Time class header
#include <NDTime.hpp> // NDTime is a C++ class that implements time operations and allows defining the time as in digital clock format (“hh:mm:ss:mss”) or as a list of integer elements ({ hh, mm, ss, mss})

//Data structures
#include "../../data_structures/cluster_config.hpp"

//Util
#include "../../util/random.hpp"

//Atomic model headers
#include "../../atomics/producer.hpp"

//C++ libraries
#include <iostream>
#include <string>

using namespace std;
using namespace cadmium;
//using namespace cadmium::basic_models::pdevs;

using TIME = NDTime;

/***** (1) *****/  // Input and output ports of the coupled model ( ->[InputReader + Subnet]-> )

/***** Define input port for coupled models *****/
//struct top_in : public in_port<Message_t>{};

/***** Define output ports for coupled model *****/
//struct top_out : public out_port<Message_t>{};



/***** (3) *****/
int main(void){

    TIME::startDeepView(); // hrs::mins:secs:mills:micrs::nns:pcs::fms
    

    // ArrivalTimes parameter
    //struct ArrivalRate_t {
    //    TIME    time_{};     // hrs::mins:secs:mills:micrs::nns:pcs::fms
    //    double  lambda_{};
    //} intervals_[5]
    //= { {{0}, 0.1}, {{0,0,0,0,50}, 0.15}, {{0,0,0,0,100}, 0.2}, {{0,0,0,0,150}, 0.25}, {{0,0,0,0,200}, 0} };
//
    //std::map<TIME, double> arrivalRates_{};
    //
    //for (auto const& inter : intervals_) {
    //    arrivalRates_[inter.time_] = inter.lambda_;
    //}

    ClusterConfig_t cluster_cfg{};
    //std::cout<<"distr: " << cluster_cfg.operProps_["op1"].distribution()<<"\n";

/****** Productor atomic model instantiation *******************/
    shared_ptr<dynamic::modeling::model> productor;
    productor = dynamic::translate::make_dynamic_atomic_model<Producer_t, TIME, std::map<TIME, double>&>("productor", cluster_cfg.arrivalRates_);


/******* TOP MODEL ********/

// Ports: data type used to defined input and output ports. It is defined in <cadmium/modeling/dynamic_model.hpp>
    // Ports = std::vector<std::type_index>
    dynamic::modeling::Ports iports_TOP; // The coupled model hasn't input port TOP. ( [ ->(in)(InputReader)(out)->(in)(Subnet)(out)-> ](top_out) -> )
    iports_TOP = {};
    dynamic::modeling::Ports oports_TOP;
    oports_TOP = {};//{typeid(top_out)}; // typeid: provide the type of a port (top_out = out_port<Message_t>)


// Models: data type(vector) used to define the components of a coupled model.  It contains the instances of submodels inside the coupled model.
    dynamic::modeling::Models submodels_TOP; // models = vector<shared_ptr<cadmium::dynamic::modeling::model>>
    submodels_TOP = {productor};


// EICs, EOCs, ICs (vectors)
    // External Input Couplings. Vector with elements of type EIC. Is used to create an EIC structure. Takes template parameters of the types of the input ports of the coupled model and the submodel inside the coupled model, in this specific order (i.e. from – to).
    dynamic::modeling::EICs eics_TOP; // The model hasn't EICs
    eics_TOP = {
        // dynamic::translate::make_EIC<FROM, TO>(model_to). FROM input port of coupled model ( ->[->InputReader + Subnet] ) TO input port submodel (->InputReader).
    }; 
    
    // External Output Couplings. Vector with elements of type EOC. Is a data type similar to EICs above, but for the External Output Couplings.
    dynamic::modeling::EOCs eocs_TOP;
    eocs_TOP = {
        //dynamic::translate::make_EOC<Producer_t<TIME>::defs::out, top_out>("productor") //  FROM output port of submodel (Subnet->) TO output port coupled model ( [InputReader + Subnet->]-> ).
    };
    
    // ICs is a data type to define internal couplings. Vector that takes elements of type IC, used to define each internal connection.
    dynamic::modeling::ICs ics_TOP;
    ics_TOP = {
        // It uses the type of the output port of the submodel “from” and the type of the input port of the submodel “to”, in this specific order. 
        //dynamic::translate::make_IC<iestream_input_defs<Message_t>::out, Subnet_defs::in>("input_reader","subnet1") // FROM output port of InputReader submodel (InputReader->) TO input port Subnet submodel (-> Subnet) =  ( [InputReader(out) -> (int)Subnet] ).
    };


// Build coupled model
    shared_ptr<dynamic::modeling::coupled<TIME>> TOP; // Constructor: (1) model name, (2) Models representing the subcomponents, (3) Ports for the input ports, (4) Ports for the output ports, (5)  EICs for external input couplings, (6)  EOCs for external output couplings and (7)  ICs for internal couplings. The constructor of this class takes all these parameters in this specific order.
    TOP = make_shared<dynamic::modeling::coupled<TIME>>(
        "TOP", submodels_TOP, iports_TOP, oports_TOP, eics_TOP, eocs_TOP, ics_TOP 
    );


/*************** Loggers *******************/
    static ofstream out_messages("simulation_results/unitary/producer_test_output_messages.txt");
    struct oss_sink_messages {  // We then define the structure oss_sink_messages to tell the simulator where we will save the message log
        static ostream& sink(){          
            return out_messages;
        }
    };
    static ofstream out_state("simulation_results/unitary/producer_test_output_state.txt");
    struct oss_sink_state {     // We define the structure oss_sink_state to tell the simulator where to save the state log
        static ostream& sink(){          
            return out_state;
        }
    };
    
    using log_state       = logger::logger<logger::logger_state,       dynamic::logger::formatter<TIME>, oss_sink_state>; //  The state log generates the global time when a state on the top model changes, and the states of all the atomic models at that time.
    using log_messages    = logger::logger<logger::logger_messages,    dynamic::logger::formatter<TIME>, oss_sink_messages>;
    // Also, include the global time of the simulation inside the state and message
    using global_time_mes = logger::logger<logger::logger_global_time, dynamic::logger::formatter<TIME>, oss_sink_messages>;
    using global_time_sta = logger::logger<logger::logger_global_time, dynamic::logger::formatter<TIME>, oss_sink_state>;

    // Once we have declared all the loggers we need, we have to combine them, so our simulation generates all the logs at the same time.
    using logger_top = logger::multilogger<log_state, log_messages, global_time_mes, global_time_sta>;


/************** Runner call ************************/ 
    dynamic::engine::runner<NDTime, logger_top> r(TOP, {0}); // runner class defined in <cadmium/engine/pdevs_dynamic_runner.hpp>. Init time to 0
    //r.run_until(NDTime("04:00:00:000"));
    r.run_until_passivate(); // Run the simulation until all models are passivated
    return 0;
}
