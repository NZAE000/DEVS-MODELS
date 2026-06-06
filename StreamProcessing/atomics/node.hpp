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
#include "../util/random.hpp"

using namespace cadmium;
using namespace std;

/*Call order: external, time_avance, output, internal*/

namespace streamprcss {

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

    // ports definition: tuple for distintes types of messages
    // NOTA: The 'typename' specifies that Node_defs::in and Node_defs::out aredatatypesthatwilloverwritethetemplateclassinthesimulator
    //"typename" indicates that the expression that follows is a "data type" (not a specific object).
    using input_ports  = tuple<typename Node_defs::in_source, typename Node_defs::in>;
    using output_ports = tuple<typename Node_defs::out>;


    // State definition (state variables of the Node_t model)
    struct state_type {

        state_type(uint32_t n_cores) 
        : taskman_{n_cores} {}

        FLINK::nodeId_t              id_ {nextID++};
        bool                         processing_{false};
        mutable FLINK::TaskManager_t taskman_{1};
    };
    state_type state{1};
    
    Node_t() noexcept {} // Default constructor

    Node_t(FLINK::JobManager_t& jman, uint32_t n_cores) noexcept
    :  state{n_cores}, jobman_{jman} {}

    // Internal transition
    void internal_transition() 
    {
        // Terminate what was executed.
        std::vector<FLINK::slotId_t> const& slot_ids_used { state.taskman_.terminatePriorityExecutions() };
        
        // Before, schedule pending requeriments (if there are pending). 
        for (auto& location : this->internal_pendings_){
            state.taskman_.scheduleExec(location.mssg_id_, location.slot_id_, jobman_);
        } internal_pendings_.clear(); // Clear pendings.

        // Then, know if there are queued executions of the slot to execute.
        for (auto slot_id_used : slot_ids_used){
            state.taskman_.checkQueuedExecution(slot_id_used, jobman_);
        }
        //std::cout<<"[slave internal "<<state.id<< "]: terminate prior execution\n";

        // Is there some pending execution? get his execution time and set processing to active.
        if (state.taskman_.pendingExecutions())
        {            
            std::vector<FLINK::Subtask_t*>& execs_prior { this->state.taskman_.getPriorityExecutions() };
            TIME lapse_prioriry { std::numeric_limits<TIME>::max() };

            for (auto& subtask : execs_prior)
                if (subtask->lapse_ < lapse_prioriry) lapse_prioriry = subtask->lapse_;

            this->lapse_time_       = lapse_prioriry;  // Update lapse.
            this->state.processing_ = true;
            //std::cout<<"\t[slave] pending exec: "<< this->lapse_time_ <<"\n";

        }
        else state.processing_ = false;
    }

    // External transition. Params: the elapsed time (e) and a bag of message (mbs).
    // make_message_bags<>: is a template data type that the simulator needs (found in <cadmium/modeling/message_bag.hpp>)
    // (Here (in this model), mbs is a tuple of one bag: the message bag in port in. The messages inside the set of messages in the bag are stored in a C++ vector.)
    void external_transition(TIME e, typename make_message_bags<input_ports>::type mbs) // std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
    {   
        vector<OperatorLocation_t>& bag = get_messages<typename Node_defs::in>(mbs);
        //if (bag.size())
            //std::cout<<"\n[slave external "<<state.id<< "]: message "<<*bag.begin().base()<<" recivied\n";

        checkExternalTransitionFromSwitch(mbs); // Check some location message of switch

        std::vector<FLINK::Subtask_t*>& execs_prior    { this->state.taskman_.getPriorityExecutions() };
        TIME                            lapse_prioriry { std::numeric_limits<TIME>::max()             };

        if (this->state.processing_) 
        {
            for (auto& subtask : execs_prior)
            {
                bool recently = bag.size() && bag[0].mssg_id_ == subtask->mssg_id_;
                if (subtask->lapse_ >= e && !recently)
                    subtask->lapse_ -= e; // Minus time left (e = elapsed time value since last transition).
                if (subtask->lapse_ < lapse_prioriry) lapse_prioriry = subtask->lapse_;
            }
        }
        else {
            for (auto& subtask : execs_prior)
                if (subtask->lapse_ < lapse_prioriry) lapse_prioriry = subtask->lapse_;
            state.processing_ = true;
        }      
        lapse_time_ = lapse_prioriry;
        //std::cout<<"[slave external "<<state.id<< "]: time execution: "<<lapse_time_ <<"\n";
    }

    // Confluence transition
    void confluence_transition(TIME e, typename make_message_bags<input_ports>::type mbs) { // mbs = std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
        // Default definition
        ////std::cout<<"ACA padre: "<<*get_messages<typename Node_defs::in_source>(mbs).begin()<<"\n";
        internal_transition();
        external_transition(TIME(), std::move(mbs)); // move(std::tuple<message_bag<Ps>...> / Ps = ports 'in').
    }

    // Output function
    typename make_message_bags<output_ports>::type output() const 
    {
        typename make_message_bags<output_ports>::type bags; // Therefore, bags is a tuple whose elements are the message bags available on the different output ports.
        vector<OperatorLocation_t> bag_out_port;             // To build the message bag for the output port 'out'.
        //std::cout<<"[slave output "<<state.id<< "]: searchNextOperatorDestinations\n";
        searchNextOperatorDestinations(bag_out_port);
        // get_messages uses a template parameter for the port we want to access, in this case, the port 'out'.
        // The function parameter is the bag of messages we want to access, in this case bags.
        get_messages<typename Node_defs::out>(bags) = bag_out_port; // vector<OperatorLocation_t> = bag_out_port
        return bags;
    }

    // time_advance function:  if we are processing, the time advance is 3 seconds. If we do not transmit, the model passivates.
    TIME time_advance() const 
    {
        // TIME next_interval;
        if (state.processing_) return lapse_time_; // Lapse: hrs::mins:secs:mills:(micrs)::nns:pcs::fms
        else                  return numeric_limits<TIME>::infinity();
        
        //return next_interval;
    }

    // Once all the DEVS functions are defined, we specify how we want to output the state of the model in the state log.
    // In this case, we only display two of the state variables: index and processing.
    // That sentence typename Node_t<TIME>::state_typ means that we are accessing the structure state_type inside the template class Node_t<TIME>.
    // We need to declare the operator using the keyword 'friend's to specify that the function can access the private members of the structure state_type.
    friend ostringstream& operator<<(ostringstream& os, const typename Node_t<TIME>::state_type& i) { // State log
        //os <<"node_"<<i.id<<": buff: "<<i.buffer<<" & sent loc: " << i.index << " & processing: " << i.processing; 
        os<<"processing: " << i.processing_ << ", buffer executions: " << i.taskman_.pendingExecutions()<<", executing: "<<i.taskman_.executing()<<","; // TODO.
        for (auto const& [id, slot] : i.taskman_.getSlots())
        {
            os<<" [slot_"<<id<<"->"<<slot.getOperator()<<": active: "<<slot.isActive()<<", using: "<<slot.isUsing()<<", tuples: "<<slot.nTuples() <<"]";
        }
        return os;
    }


    FLINK::TaskManager_t&       getTaskManager()       noexcept { return state.taskman_;  }
    FLINK::TaskManager_t const& getTaskManager() const noexcept { return state.taskman_;  }
    FLINK::nodeId_t             id()                   noexcept { return state.id_;       }

protected: // Son access (node_master).

    void checkExternalTransitionFromSwitch(typename make_message_bags<input_ports>::type& mbs)
    {   
        vector<OperatorLocation_t>
        bag_in_port = get_messages<typename Node_defs::in>(mbs); // To retrieve the bag (return vector message(in this case get messages of port in_source<OperatorLocation_t>) for us).
        
        auto size_bag { bag_in_port.size() };
        if (size_bag > 1) assert(false && "One message at a time");
        
        if (size_bag) {
            auto const [mssg_id, _, slot_id] = *bag_in_port.begin();
            state.taskman_.scheduleExec(mssg_id, slot_id, jobman_); // SHCEDULE ON SPECIFIC SLOT.
        }
        //else{ //std::cout<<"\nno switch\n"; }
    }

    void searchNextOperatorDestinations(vector<OperatorLocation_t>& bag_out_port) const
    {
        // Find less lapse execution.
        std::vector<FLINK::Subtask_t*>& execs_prior { this->state.taskman_.getPriorityExecutions() };
        TIME lapse_prioriry { std::numeric_limits<TIME>::max() };
        for (auto& subtask : execs_prior){
            if (subtask->lapse_ < lapse_prioriry) lapse_prioriry = subtask->lapse_;
        }
        
        // Then get the operator that was running for get their next destinations.
        for (auto& subtask : execs_prior){
            if (subtask->lapse_ == lapse_prioriry) 
            {
                FLINK::operId_t const& oper_id = state.taskman_.getSlot(subtask->slot_id_).getOperator(); //getOperator(exec_prior.slot_id);
                
                // Know if send message or not according operator's selectivity probability.
                double selectivity { jobman_.getOperatorProperties(oper_id).selectivity_ };
                if (selectivity < 1.0 && unidistr_.generate() > selectivity) continue; // Don't send mensaje to destination.
                
                if (!jobman_.lastOperator(oper_id)) // Haven't reached the last operator?
                {
                    this->jobman_.accumSentRecords(oper_id, 1); // Accumulate send messages.
                    
                    vector<FLINK::operId_t const*> const& 
                    operDestinations = jobman_.getOperatorDestinations(oper_id);
                    
                    // Get balanced destiny locations for each destiny opeartor.
                    for (auto const* oper_id_des : operDestinations) {
                        //if (*oper_id_des == "nexmarkq26writer")
                        //    std::cout<<"size: "<<operDestinations.size()<< " oper_id: "<<oper_id_des<<'\n';
                        OperatorLocation_t location = jobman_.getOperLocationLessload(*oper_id_des);
                        location.mssg_id_ = subtask->mssg_id_; // Pass message.

                        // Location in this node? store local pending.
                        if (location.node_id_ == state.id_){
                            //state.taskman_.scheduleExec(location.mssg_id, location.slot_id, jobman_);
                            internal_pendings_.emplace_back(location);
                        }
                        else { // The operator is in other node.
                            bag_out_port.push_back(location); 
                        }
                        //std::cout<<"\toper priority exec: "<<oper_id<<", and next: "<<*oper_id_des<<" in location node: "<<location.node_id<<" slot: "<<location.slot_id<<"\n";
                    }
                }
                //else { // TODO !!
                //    std::cout<<"\tLast: "<<oper_id<<'\n';
                //} 
            }
        }
    }   


    //const TIME exec_time_{0,0,0,0,5}; // Excecution time
protected:
    TIME                    lapse_time_{0}; // Time left until next departure.
    FLINK::JobManager_t&    jobman_;

private:
    inline static FLINK::nodeId_t       nextID {0};
    mutable vector<OperatorLocation_t>  internal_pendings_{}; 
    mutable myrandom::Uniform_t         unidistr_{0.0, 1.0};
};

} // namespace streamprcs

#endif // _NODE_HPP__