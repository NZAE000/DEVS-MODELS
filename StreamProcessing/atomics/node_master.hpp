/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Node master implementation
*/
#ifndef _NODE_MASTER_HPP__
#define _NODE_MASTER_HPP__

#include "node.hpp"


template<typename TIME> 
class NodeMaster_t : public Node_t<TIME> { // Node master is an atomic node

public:

    // Default constructor
    NodeMaster_t() noexcept
    : Node_t<TIME>{} {}

    NodeMaster_t(FLINK::JobManager_t& jman) noexcept
    : Node_t<TIME>{jman} {}


    // Internal transition
    void internal_transition()
    {
        if (there_external_locations()){
            //std::cout<<"ACA1\n";
            externLocations.clear();
            if (this->taskman_.executionPending())
            {
                FLINK::Subtask_t& exec_prior { this->taskman_.getPriorityExecution() };
                this->lapse_time_      = exec_prior.lapse_;  // Update lapse.
                this->state.processing = true;
                std::cout<<"[internal] lapse: "<< this->lapse_time_ <<"\n";

            } else this->state.processing = false;
        }
        else { 
            //std::cout<<"ACA2\n";
            static_cast<Node_t<TIME>*>(this)->internal_transition(); // Cast to super to call Node_t's internal transition algorithm.
        }
    }
    
    // External transition
    void external_transition(TIME e, typename make_message_bags<typename Node_t<TIME>::input_ports>::type mbs)  // std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
    {
        //std::cout<<"node master\n";
        check_external_transition_from_producer(mbs);      // Check some message of producer.
        this->check_external_transition_from_switch(mbs);  // Check some location message of switch.

        if (there_external_locations()){ // Do you have to send messages to other locations immediately?
            this->lapse_time_ = {0};     // Imminent for the output to the switch.
        }
        else if (this->taskman_.executionPending())
        {
            FLINK::Subtask_t& exec_prior { this->taskman_.getPriorityExecution() };
            if (this->state.processing) 
                exec_prior.lapse_ -= e;             // Minus time left (e = elapsed time value since last transition).
            this->lapse_time_ = exec_prior.lapse_;  // Update lapse.
            
            std::cout<<"[external] lapse: "<< this->lapse_time_ <<"\n";
        }
        this->state.processing = true;

        //++this->state.buffer; // get this out already!
    }

    // Confluence transition
    void confluence_transition(TIME e, typename make_message_bags<typename Node_t<TIME>::input_ports>::type mbs) { // mbs = std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
        // Default definition
        //std::cout<<"ACA son: "<<*get_messages<typename Node_defs::in_source>(mbs).begin()<<"\n";
        internal_transition();
        external_transition(TIME(), std::move(mbs)); // move(std::tuple<message_bag<Ps>...> / Ps = ports 'in').
    }

    // Output function
    typename make_message_bags<typename Node_t<TIME>::output_ports>::type output() const
    {   
        typename make_message_bags<typename Node_t<TIME>::output_ports>::type bags; // Therefore, bags is a tuple whose elements are the message bags available on the different output ports.
        vector<OperatorLocation_t> bag_port_out;                                    // To build the message bag for the output port 'out'.

        if (there_external_locations()){        // Do you have to send messages to other locations immediately?
            bag_port_out = externLocations;
        }
        else this->search_next_operator_destinations(bag_port_out); // Normal output: send new destinations for next operation.

        get_messages<typename Node_defs::out>(bags) = bag_port_out; // vector<OperatorLocation_t> = bag_port_out
        return bags;
    }

private:
    mutable vector<OperatorLocation_t> externLocations{}; 

    bool there_external_locations() const noexcept { return externLocations.size(); }

    void check_external_transition_from_producer(typename make_message_bags<typename Node_t<TIME>::input_ports>::type& mbs)  // std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
    {
        // get_messages<>: to get the message bag from the port (in this case input port).
        // Uses a template parameter for the port we want to access, in this case, the 'in' port, defined by typename NodeMaster_defs::in.
        vector<Message_t> 
        bag_port_in_src = get_messages<typename Node_defs::in_source>(mbs); // To retrieve the bag (return vector message(in this case get messages of port in_source<OperatorLocation_t>) for us).
        auto size_bag { bag_port_in_src.size() };
        if (size_bag > 1) assert(false && "One message at a time");

        if (size_bag) // Are there a message from the producer?
        {
            // Find less congested location of first operator.
            FLINK::operId_t first_op_id   = this->jobman_.firstOperator();
            OperatorLocation_t const& loc = this->jobman_.getOperLocation_balanced(first_op_id);

            if (loc.node_id == this->state.id){ // Chosen location on this node?
                //std::cout<<"este nodo\n";
                this->taskman_.scheduleExec(loc.slot_id, this->jobman_); // SCHEDULE ON SPECIFIC SLOT.
            }
            else {
                externLocations.emplace_back(loc); // Location messages for elsewhere.
                //std::cout<<"otro nodo\n";
            }
        }
    }
};

#endif // _NODE_MASTER_HPP__