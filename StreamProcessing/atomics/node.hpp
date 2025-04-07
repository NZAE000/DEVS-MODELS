/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Node implementation
*/
#ifndef _NODE_HPP__
#define _NODE_HPP__

#include <cadmium/modeling/ports.hpp>
#include <cadmium/modeling/message_bag.hpp> // Used to declare a bag of messages for input or output port.

#include <limits>
#include <assert.h>
#include <string>
#include <random>
#include <iostream>

#include "../data_structures/operator_location.hpp"
#include "../data_structures/message.hpp"
#include "../data_structures/flink/jobmanager.hpp"

using namespace cadmium;
using namespace std;

/*Call order: external, time_avance, output, internal*/

//Port definition
struct Node_defs {
    struct in_source  : public in_port<Message_t> {};
    struct in         : public in_port<OperatorLocation_t> {};  
    struct out        : public out_port<OperatorLocation_t> {};  
};

// Atomic model
template<typename TIME> 
class Node_t { 

public:

    FLINK::TaskManager_t& getTaskManager() noexcept { return state.taskman_;  }
    FLINK::nodeId_t id()                   noexcept { return state.id;        }

    // ports definition: tuple for distintes types of messages
    // NOTA: The 'typename' specifies that Node_defs::in and Node_defs::out aredatatypesthatwilloverwritethetemplateclassinthesimulator
    //"typename" indicates that the expression that follows is a "data type" (not a specific object).
    using input_ports  = tuple<typename Node_defs::in_source, typename Node_defs::in>;
    using output_ports = tuple<typename Node_defs::out>;


    // State definition (state variables of the Node_t model)
    struct state_type {
        FLINK::nodeId_t id {nextID++};
        bool processing{false};           // Used to define that the model has something to output
        mutable FLINK::TaskManager_t taskman_{};
        //uint32_t index{};                 // Counts the location that went send
        //uint32_t buffer{};                // Store received messages
    };
    state_type state;

    // Default constructor
    Node_t() noexcept {}

    Node_t(FLINK::JobManager_t& jman) noexcept
    : jobman_{jman} {}

    // Internal transition
    void internal_transition() 
    {
        FLINK::slotId_t slot_id_used = state.taskman_.terminatePriorityExecution();   // Terminate what was executed.
        state.taskman_.checkQueuedExecution(slot_id_used, jobman_);                   // Know if there are queued executions of the slot to execute.
        std::cout<<"[slave internal "<<state.id<< "]: terminate prior execution\n";

        // Is there some pending execution? get his execution time and set processing to active.
        if (state.taskman_.executionPending())
        {
            FLINK::Subtask_t& exec_prior { state.taskman_.getPriorityExecution() };
            lapse_time_      = exec_prior.lapse_;
            state.processing = true;
            std::cout<<"\t[slave] pending exec: "<< this->lapse_time_ <<"\n";
        }
        else state.processing = false;
    }

    // External transition. Params: the elapsed time (e) and a bag of message (mbs).
    // make_message_bags<>: is a template data type that the simulator needs (found in <cadmium/modeling/message_bag.hpp>)
    // (Here (in this model), mbs is a tuple of one bag: the message bag in port in. The messages inside the set of messages in the bag are stored in a C++ vector.)
    void external_transition(TIME e, typename make_message_bags<input_ports>::type mbs) // std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
    {
        check_external_transition_from_switch(mbs); // Check some location message of switch

        FLINK::Subtask_t& exec_prior { state.taskman_.getPriorityExecution() };
        if (state.processing) exec_prior.lapse_ -= e;   // Minus time left (e = elapsed time value since last transition).
        else state.processing = true;

        lapse_time_ = exec_prior.lapse_;
        std::cout<<"[slave external "<<state.id<< "]: time execution: "<<lapse_time_ <<"\n";

    }

    // Confluence transition
    void confluence_transition(TIME e, typename make_message_bags<input_ports>::type mbs) { // mbs = std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
        // Default definition
        //std::cout<<"ACA padre: "<<*get_messages<typename Node_defs::in_source>(mbs).begin()<<"\n";
        internal_transition();
        external_transition(TIME(), std::move(mbs)); // move(std::tuple<message_bag<Ps>...> / Ps = ports 'in').
    }

    // Output function
    typename make_message_bags<output_ports>::type output() const 
    {
        typename make_message_bags<output_ports>::type bags; // Therefore, bags is a tuple whose elements are the message bags available on the different output ports.
        vector<OperatorLocation_t> bag_port_out;             // To build the message bag for the output port 'out'.
        std::cout<<"[slave output "<<state.id<< "]: search_next_operator_destinations\n";
        search_next_operator_destinations(bag_port_out);
        // get_messages uses a template parameter for the port we want to access, in this case, the port 'out'.
        // The function parameter is the bag of messages we want to access, in this case bags.
        get_messages<typename Node_defs::out>(bags) = bag_port_out; // vector<OperatorLocation_t> = bag_port_out
        return bags;
    }

    // time_advance function:  if we are processing, the time advance is 3 seconds. If we do not transmit, the model passivates.
    TIME time_advance() const 
    {
        // TIME next_interval;
        if (state.processing) return lapse_time_; // Lapse: hrs::mins:secs:mills:(micrs)::nns:pcs::fms
        else                  return numeric_limits<TIME>::infinity();
        
        //return next_interval;
    }

    // Once all the DEVS functions are defined, we specify how we want to output the state of the model in the state log.
    // In this case, we only display two of the state variables: index and processing.
    // That sentence typename Node_t<TIME>::state_typ means that we are accessing the structure state_type inside the template class Node_t<TIME>.
    // We need to declare the operator using the keyword 'friend's to specify that the function can access the private members of the structure state_type.
    friend ostringstream& operator<<(ostringstream& os, const typename Node_t<TIME>::state_type& i) { // State log
        //os <<"node_"<<i.id<<": buff: "<<i.buffer<<" & sent loc: " << i.index << " & processing: " << i.processing; 
        os <<"processing: " << i.processing << ", buffer executions: " << i.taskman_.executionPending()<<", slots states:";
        for (auto const& [id, slot] : i.taskman_.getSlots())
        {
            os << " [slot "<<id<<": tuples: "<<slot.nTuples() << ", active: "<<slot.isRunnig()<<"]";
        }
        return os;
    }


protected: // Son access (node_master).

    void check_external_transition_from_switch(typename make_message_bags<input_ports>::type& mbs)
    {   
        vector<OperatorLocation_t>
        bag_port_in = get_messages<typename Node_defs::in>(mbs); // To retrieve the bag (return vector message(in this case get messages of port in_source<OperatorLocation_t>) for us).
        auto size_bag { bag_port_in.size() };
        if (size_bag > 1) assert(false && "One message at a time");
        
        if (size_bag) {
            auto const [_, slot_id] = *bag_port_in.begin();
            state.taskman_.scheduleExec(slot_id, jobman_); // SHCEDULE ON SPECIFIC SLOT.
        }
        //else{ std::cout<<"\nno switch\n"; }
    }

    void search_next_operator_destinations(vector<OperatorLocation_t>& bag_port_out) const
    {
        // Get the operator that was running for get their next destinations
        FLINK::Subtask_t const& exec_prior = state.taskman_.getPriorityExecution();
        FLINK::operId_t  const& oper_id    = state.taskman_.getSlot(exec_prior.slot_id).getOperator(); //getOperator(exec_prior.slot_id);

        if (oper_id != jobman_.lastOperator()) // Haven't reached the last operator?
        {
            vector<FLINK::operId_t> const& operDestinations = jobman_.getOperatorDestinations(oper_id);

            // Get balanced destiny locations for each destiny opeartor.
            bag_port_out.reserve(operDestinations.size());
            for (auto const& oper_id_des : operDestinations) 
            {
                OperatorLocation_t const& location = jobman_.getOperLocation_balanced(oper_id_des);

                // Location in this node? schedule execution now.
                if (location.node_id == state.id){
                    state.taskman_.scheduleExec(location.slot_id, jobman_);
                }
                else { // The operator is in other node.
                    bag_port_out.push_back(location);
                    //std::cout<<"acaca\n";   
                }
                std::cout<<"\toper priority exec: "<<oper_id<<", and next: "<<oper_id_des<<" in location node: "<<location.node_id<<" slot: "<<location.slot_id<<"\n";
            }
        }
        else { std::cout<<"\tlast\n"; } // TODO !!
    }   


    //const TIME exec_time_{0,0,0,0,5}; // Excecution time
    TIME lapse_time_{0}; // Time left until next departure
    FLINK::JobManager_t& jobman_;

private:
    inline static FLINK::nodeId_t nextID {0};
};

#endif // _NODE_HPP__