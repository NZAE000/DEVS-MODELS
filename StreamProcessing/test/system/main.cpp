//Cadmium Simulator headers
#include <cadmium/modeling/ports.hpp>
#include <cadmium/modeling/dynamic_model.hpp>
#include <cadmium/modeling/dynamic_model_translator.hpp>
#include <cadmium/engine/pdevs_dynamic_runner.hpp>
#include <cadmium/logger/common_loggers.hpp>
#include <boost/preprocessor/repetition/repeat.hpp>
#include <boost/preprocessor/cat.hpp>
#include <boost/preprocessor/stringize.hpp> // To convert type names to strings.

//Time class header
#include <NDTime.hpp> // NDTime is a C++ class that implements time operations and allows defining the time as in digital clock format (“hh:mm:ss:mss”) or as a list of integer elements ({ hh, mm, ss, mss})

//Data structures
#include "../../data_structures/cluster_config.hpp"
//#include "../../data_structures/flink/jobmanager.hpp"
#include "../../data_structures/flink/jobmanager.tpp"

//Atomic model headers
#include "../../atomics/producer.hpp"
#include "../../atomics/node_master.hpp"
#include "../../atomics/switch.hpp"

//C++ libraries
#include <iostream>
#include <string>

using namespace std;
using namespace cadmium;
//using namespace cadmium::basic_models::pdevs;

using TIME = NDTime;

// Input and output ports of the Cluster coupled model
namespace Cluster_defs {
    struct in : public in_port<Message_t> {};
}


int main(void){

    TIME::startDeepView(); // extend to hrs::mins:secs:mills:micrs::nns:pcs::fms

    ClusterConfig_t     cluster_cfg{};
    FLINK::JobManager_t JobManager{cluster_cfg};

    //std::cout<<"distr: " << cluster_cfg.operProps_["op1"].distribution()<<"\n";

/****** Productor atomic model instantiation *******************/
    shared_ptr<dynamic::modeling::model> productor;
    productor = dynamic::translate::make_dynamic_atomic_model<Producer_t, TIME, std::map<TIME, double>&>("productor", cluster_cfg.arrivalRates_, "simulation_results/system/rate_change.txt");

/****** Node master atomic model instantiations *******************/
    std::vector<shared_ptr<dynamic::modeling::model>> abstract_nodes{};
    JobManager.deployJob([&](uint32_t nNodes, uint32_t nCores, std::vector<Node_t<TIME>*>& nodes)
    {
        abstract_nodes.reserve(nNodes);
        nodes.reserve(nNodes);

        // Create always first node (master=node_0).
        abstract_nodes.emplace_back(dynamic::translate::make_dynamic_atomic_model<NodeMaster_t, TIME, FLINK::JobManager_t&>("node_0", JobManager, nCores));
        nodes.push_back(dynamic_cast<Node_t<TIME>*>(abstract_nodes.begin()->get()));

        // Create slave nodes (node_1, node_2, ..., node_n).
        std::string name_base{"node_"}, fullname{};
        for (uint32_t id=1; id<nNodes; ++id)
        {
            fullname = name_base + std::to_string(id);
            abstract_nodes.emplace_back(dynamic::translate::make_dynamic_atomic_model<Node_t, TIME, FLINK::JobManager_t&>(fullname, JobManager, nCores));
            nodes.push_back(dynamic_cast<Node_t<TIME>*>((abstract_nodes.begin() + id)->get())); // Next interation, get down to subclase (atomic_model -> node) and store address.
        }
    });
    
/****** Switch atomic model instantiation *******************/
    shared_ptr<dynamic::modeling::model> sswitch;
    sswitch = dynamic::translate::make_dynamic_atomic_model<Switch_t, TIME>("switch");


    //Node_t<TIME>& node_m = dynamic_cast<Node_t<TIME>&>(*nodes.begin()->get());
    //FLINK::operId_t oper1 = node_m.getTaskManager().getOperator(0);
    //FLINK::operId_t oper2 = node_m.getTaskManager().getOperator(1);
    //FLINK::operId_t oper3 = node_m.getTaskManager().getOperator(2);
    //FLINK::operId_t oper4 = node_m.getTaskManager().getOperator(3);
    //FLINK::operId_t oper5 = node_m.getTaskManager().getOperator(4);
//
    //std::cout<<oper1<<" "<<oper2<<" "<<oper3<<" "<<oper4<<" "<<oper5<<"\n";

/******* CLUSTER COUPLED MODEL ********/

// Ports: std::vector<std::type_index>
    dynamic::modeling::Ports iports_Cluster = { typeid(Cluster_defs::in) };
    dynamic::modeling::Ports oports_Cluster = {};

// Submodels: std::vector<shared_prt<..::model>>
    dynamic::modeling::Models submodels_Cluster = abstract_nodes;
    submodels_Cluster.push_back(sswitch); // This might duplicate capacity!!

// eics, eocs, ics
    dynamic::modeling::EICs eics_Cluster = {
        dynamic::translate::make_EIC<Cluster_defs::in, Node_defs::in_source>("node_0")    // eic to node_0 = node_master   ->[->(node_0)]
    };

    // Metaprogramming at the preprocessing level with Boost Preprocessor.
    #define GENERATE_IC(z, n, data) \
    dynamic::translate::make_IC<Node_defs::out, Switch_t<TIME>::defs_port::BOOST_PP_CAT(in_, n)>(BOOST_PP_STRINGIZE(BOOST_PP_CAT(node_, n)), "switch"), \
    dynamic::translate::make_IC<Switch_t<TIME>::defs_port::BOOST_PP_CAT(out_, n), Node_defs::in>("switch", BOOST_PP_STRINGIZE(BOOST_PP_CAT(node_, n))),

    dynamic::modeling::ICs ics_Cluster = {
        BOOST_PP_REPEAT(N_NODES, GENERATE_IC, _)
    };

    //dynamic::modeling::ICs ics_Cluster = {
    //    dynamic::translate::make_IC<Node_defs::out, Switch_t<TIME>::defs_port::in_0>("node_0", "switch"),
    //    dynamic::translate::make_IC<Node_defs::out, Switch_t<TIME>::defs_port::in_1>("node_1", "switch"),
    //    dynamic::translate::make_IC<Node_defs::out, Switch_t<TIME>::defs_port::in_2>("node_2", "switch"),
    //    dynamic::translate::make_IC<Node_defs::out, Switch_t<TIME>::defs_port::in_3>("node_3", "switch"),
    //    
    //    dynamic::translate::make_IC<Switch_t<TIME>::defs_port::out_0, Node_defs::in>("switch", "node_0"),
    //    dynamic::translate::make_IC<Switch_t<TIME>::defs_port::out_1, Node_defs::in>("switch", "node_1"),
    //    dynamic::translate::make_IC<Switch_t<TIME>::defs_port::out_2, Node_defs::in>("switch", "node_2"),
    //    dynamic::translate::make_IC<Switch_t<TIME>::defs_port::out_3, Node_defs::in>("switch", "node_3"),
    //};
    //dynamic::modeling::ICs ics_Cluster;
    //ics_Cluster.reserve(nodes.size() * 2); // For each existent node, there are two ports (in, out)
    //for (auto const& node : nodes)
    //{
    //    ics_Cluster.push_back(dynamic::translate::make_IC<Node_defs::out, Switch_t<TIME>::defs_port::in_0>(node->get_id(), "switch"));
    //    ics_Cluster.push_back(dynamic::translate::make_IC<Switch_t<TIME>::defs_port::out_0, Node_defs::in>("switch", node->get_id()));
    //    // dynamic::translate::make_IC<Producer_t<TIME>::defs::out, Node_defs::in_source>("productor", "node_master") // FROM output port of productor submodel (Prod->) TO input port node submodel (-> Node) =  ( [Prod(out) -> (int)node] ).
    //}
    dynamic::modeling::EOCs eocs_Cluster = {};     // Nothing to EOC of Cluster

// Cluster
    shared_ptr<dynamic::modeling::coupled<TIME>> CLUSTER;
    CLUSTER = make_shared<dynamic::modeling::coupled<TIME>>(    // MAKE Cluster COUPLED
        "Cluster", submodels_Cluster, iports_Cluster, oports_Cluster, eics_Cluster, eocs_Cluster, ics_Cluster 
    );

/******* TOP COUPLED MODEL ********/

// Ports: data type used to defined input and output ports. It is defined in <cadmium/modeling/dynamic_model.hpp>
    // Ports = std::vector<std::type_index>
    dynamic::modeling::Ports iports_TOP; // The coupled model hasn't input port TOP. ( [ ->(in)(InputReader)(out)->(in)(Subnet)(out)-> ](top_out) -> )
    iports_TOP = {};
    dynamic::modeling::Ports oports_TOP;
    oports_TOP = {};//{typeid(top_out)}; // typeid: provide the type of a port (top_out = out_port<Message_t>)


// Models: data type(vector) used to define the components of a coupled model.  It contains the instances of submodels inside the coupled model.
    dynamic::modeling::Models submodels_TOP; // models = vector<shared_ptr<cadmium::dynamic::modeling::model>>
    submodels_TOP = {productor, CLUSTER};


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
        dynamic::translate::make_IC<Producer_t<TIME>::defs::out, Cluster_defs::in>("productor", "Cluster") // FROM output port of InputReader submodel (InputReader->) TO input port Subnet submodel (-> Subnet) =  ( [InputReader(out) -> (int)Subnet] ).
    };


// Build coupled model
    shared_ptr<dynamic::modeling::coupled<TIME>> TOP; // Constructor: (1) model name, (2) Models representing the subcomponents, (3) Ports for the input ports, (4) Ports for the output ports, (5)  EICs for external input couplings, (6)  EOCs for external output couplings and (7)  ICs for internal couplings. The constructor of this class takes all these parameters in this specific order.
    TOP = make_shared<dynamic::modeling::coupled<TIME>>(
        "TOP", submodels_TOP, iports_TOP, oports_TOP, eics_TOP, eocs_TOP, ics_TOP 
    );


/*************** Loggers *******************/
    static ofstream out_messages("simulation_results/system/system_test_output_messages.txt");
    struct oss_sink_messages {  // We then define the structure oss_sink_messages to tell the simulator where we will save the message log
        static ostream& sink(){          
            return out_messages;
        }
    };
    static ofstream out_state("simulation_results/system/system_test_output_state.txt");
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
    //auto time1 = NDTime{0,0,0,0,200};
    //auto time2 = time1 + NDTime("00:00:00:000:900");
    //std::cout<<"time: "<<time2<<"\n";
    
    return 0;
}
