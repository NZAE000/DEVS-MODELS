/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Node master implementation
*/
#ifndef _NODE_MASTER_HPP__
#define _NODE_MASTER_HPP__

#include "node.hpp"

namespace streamprcss {

template<typename TIME> 
class NodeMaster_t : public Node_t<TIME> { // Node master is an atomic node

public:

    // Default constructor.
    NodeMaster_t() noexcept
    : Node_t<TIME>{} {}

    NodeMaster_t(FLINK::JobManager_t& jman, uint32_t n_cores) noexcept
    : Node_t<TIME>{jman, n_cores} {}


    // Internal transition.
    void internal_transition()
    {
        if (this->sendInmediatlyToSwitch()){
            //std::cout<<"[master internal]: send inmediatly to switch\n";
            extern_locations_.clear();
            if (this->state.taskman_.pendingExecutions())
            {
                std::vector<FLINK::ActiveSubtask_t*>& prior_execs { this->state.taskman_.getPriorityExecutions() };
                TIME lapse_prioriry { std::numeric_limits<TIME>::max() };

                for (auto& a_subtask : prior_execs)
                    if (a_subtask->subtask_->lapse_ < lapse_prioriry) lapse_prioriry = a_subtask->subtask_->lapse_;

                this->lapse_time_       = lapse_prioriry;  // Update lapse.
                this->state.processing_ = true;
                //std::cout<<"\t[master] pending exec: "<< this->lapse_time_ <<"\n";

            } else this->state.processing_ = false;
        }
        else {
            //std::cout<<"[call slave internal]\n";
            static_cast<Node_t<TIME>*>(this)->internal_transition(); // Cast to super to call Node_t's internal transition algorithm.

            //for (auto const& [core_id, buffer] : this->state.taskman_.getExecBuffers()) {
            //    std::cout<<"core"<<core_id<<":  "<<buffer.size()<<' ';
            //}
            //std::cout<<'\n';  
        }
    }
    
    // External transition.
    void external_transition(TIME e, typename make_message_bags<typename Node_t<TIME>::input_ports>::type mbs)  // std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
    {      

        vector<Message_t>&          prod_bag = get_messages<typename Node_defs::in_source>(mbs);
        vector<OperatorLocation_t>& bag      = get_messages<typename Node_defs::in>(mbs);
        //if (prod_bag.size()) //std::cout<<"\n[master external from prod]: message "<<prod_bag.begin()->id_<<" recivied\n";
        //if (bag.size())      //std::cout<<"\n[master external from switch]: message "<<*bag.begin().base()<<" recivied\n";

        checkExternalTransitionfromProducer(mbs);      // Check some message of producer.
        this->checkExternalTransitionFromSwitch(mbs);  // Check some location message of switch.
        
        if (this->sendInmediatlyToSwitch()){ // Do you have to send messages to other locations immediately?
            this->lapse_time_ = {0};         // Imminent for the output to the switch.
            //std::cout<<"[master external]: send inmediatly to switch"<<"\n";
        }
        else if (this->state.taskman_.pendingExecutions())
        {
            std::vector<FLINK::ActiveSubtask_t*>& prior_execs    { this->state.taskman_.getPriorityExecutions() };
            TIME                                  lapse_prioriry { std::numeric_limits<TIME>::max()             };
            if (this->state.processing_) 
            {
                for (auto& a_subtask : prior_execs)
                {
                    auto* subtask { a_subtask->subtask_ };
                    bool recently = (prod_bag.size() && prod_bag[0].id_ == subtask->mssg_id_) || (bag.size() && bag[0].mssg_id_ == subtask->mssg_id_);
                    if (subtask->lapse_ >= e && !recently){
                        subtask->lapse_ -= e; // Minus time left (e = elapsed time value since last transition).
                    }
                    if (subtask->lapse_ < lapse_prioriry) lapse_prioriry = subtask->lapse_;
                }
            }
            else {
                for (auto& a_subtask : prior_execs)
                    if (a_subtask->subtask_->lapse_ < lapse_prioriry) lapse_prioriry = a_subtask->subtask_->lapse_;
            }
            this->lapse_time_ = lapse_prioriry;  // Update lapse.
            //std::cout<<"[master external]: time execution: "<< this->lapse_time_ <<"\n";
        }
        this->state.processing_ = true;
    }

    // Confluence transition.
    void confluence_transition(TIME e, typename make_message_bags<typename Node_t<TIME>::input_ports>::type mbs) { // mbs = std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
        // Default definition
        internal_transition();
        external_transition(TIME(), std::move(mbs)); // move(std::tuple<message_bag<Ps>...> / Ps = ports 'in').
    }

    // Output function.
    typename make_message_bags<typename Node_t<TIME>::output_ports>::type output() const
    {   
        typename make_message_bags<typename Node_t<TIME>::output_ports>::type bags; // Therefore, bags is a tuple whose elements are the message bags available on the different output ports.
        vector<OperatorLocation_t> bag_port_out;                                    // To build the message bag for the output port 'out'.

        if (this->sendInmediatlyToSwitch()){        // Do you have to send messages to other locations immediately?
            bag_port_out = extern_locations_;
            auto loc     = bag_port_out.at(0);
            //std::cout<<"[master output]: send inmediatly to switch: loc "<< loc <<"\n";
        }
        else {
            //std::cout<<"[master output]: searchNextOperatorDestinations\n";
            this->searchNextOperatorDestinations(bag_port_out); // Normal output: send new destinations for next operation.
        }

        get_messages<typename Node_defs::out>(bags) = bag_port_out; // vector<OperatorLocation_t> = bag_port_out
        return bags;
    }

private:
    mutable vector<OperatorLocation_t> extern_locations_ {}; 

    bool sendInmediatlyToSwitch() const noexcept { return extern_locations_.size(); }

    void checkExternalTransitionfromProducer(typename make_message_bags<typename Node_t<TIME>::input_ports>::type& mbs)  // std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
    {
        // get_messages<>: to get the message bag from the port (in this case input port).
        // Uses a template parameter for the port we want to access, in this case, the 'in' port, defined by typename NodeMaster_defs::in.
        vector<Message_t> 
        bag_in_port_src = get_messages<typename Node_defs::in_source>(mbs); // To retrieve the bag (return vector message(in this case get messages of port in_source<Message_t>) for us).
        auto size_bag   { bag_in_port_src.size() };
        if (size_bag > 1) assert(false && "[Node master]: One message at a time");

        if (size_bag) // Are there a message from the producer?
        {
            uint32_t mssg_id = bag_in_port_src[0].id_;
            if (mssg_id != 0) // Zero if the producer is not sending any more data, he is only capturing metrics. 
            {
                // Find less congested location of first operator (source by default).
                FLINK::operId_t const& first_op_id = this->jobman_.getFirstOperator();
                OperatorLocation_t loc             = this->jobman_.getOperLocationLessload(first_op_id);
                loc.mssg_id_                       = mssg_id;

                if (loc.node_id_ == this->state.id_){ // Chosen location on this node?
                    this->state.taskman_.scheduleExec(loc.mssg_id_, loc.slot_id_, this->jobman_); // SCHEDULE ON SPECIFIC SLOT.
                }
                else {
                    extern_locations_.emplace_back(loc); // Location messages for elsewhere.
                }
            }
        }
    }
};

} // namespace streamprcs

#endif // _NODE_MASTER_HPP__