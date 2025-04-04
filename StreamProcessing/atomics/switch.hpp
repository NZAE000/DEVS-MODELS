/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Switch implementation
*/

#ifndef _SWITCH_HPP__
#define _SWITCH_HPP__

#include <cadmium/modeling/ports.hpp>
#include <cadmium/modeling/message_bag.hpp> // Used to declare a bag of messages for input or output port.

#include <limits>
#include <assert.h>
#include <string>
#include <random>
#include <iostream>
#include <vector>

#include "../data_structures/operator_location.hpp"
#include "../data_structures/message.hpp"
#include "../util/random.hpp"

using namespace cadmium;
using namespace std;

/*Call order: external, time_avance, output, internal*/

//Port definition
struct Switch_defs {
    struct in_master : public in_port<Message_t> {};
    struct out_0     : public out_port<OperatorLocation_t> {};
    struct out_1     : public out_port<OperatorLocation_t> {};
    struct out_2     : public out_port<OperatorLocation_t> {};
};

struct MessageBuffer_t {
    std::vector<OperatorLocation_t> messages{};
    bool active {false};
};

// Atomic model definition
template<typename TIME> 
class Switch_t { 

public:

    // ports definition: tuple for distintes types of messages
    // NOTA: The 'typename' specifies that Switch_defs::in and Switch_defs::out aredatatypesthatwilloverwritethetemplateclassinthesimulator
    //"typename" indicates that the expression that follows is a "data type" (not a specific object).
    using input_ports  = tuple<typename Switch_defs::in_master>;
    using output_ports = tuple<typename Switch_defs::out_0, typename Switch_defs::out_1, typename Switch_defs::out_2>;
    using nodeId_t     = uint32_t;

    // State definition (state variables of the Switch_t model)
    struct state_type {
        bool transmitting_{false};   // Used to define that the model has something to output
    };
    state_type state;

    mutable std::map<nodeId_t, MessageBuffer_t> port_buffers_; // node_id, buffer
    TIME prox_time_{};  // Time left until next departure
    TIME send_time_{};  // Send time
    int mean_ {30};

    // Default constructor
    Switch_t() noexcept
    {   
        // Init port buffers
        port_buffers_[0] = {};
        port_buffers_[1] = {};
        port_buffers_[2] = {};
    }

    // internal transition: model sets the state variable transmitting_ to false.
    void internal_transition() 
    {
        uint8_t buffers_queued{0};

        for (auto & [_, buffer] : port_buffers_) { // Are there any pending messages in any of the output port buffers?
            if (!buffer.messages.empty()) { 
                buffer.active = true;
                ++buffers_queued;
            }
        }
        if (!buffers_queued) state.transmitting_ = false;
        else send();
    }

    // external transition. Params: the elapsed time (e) and a bag of message (mbs).
    // make_message_bags<>: is a template data type that the simulator needs (found in <cadmium/modeling/message_bag.hpp>)
    // (Here (in this model), mbs is a tuple of one bag: the message bag in port in. The messages inside the set of messages in the bag are stored in a C++ vector.)
    void external_transition(TIME e, typename make_message_bags<input_ports>::type mbs)  // std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
    {
        vector<Message_t> bag_port_in;
        // get_messages<>: to get the message bag from the port (in this case input port).
        // Uses a template parameter for the port we want to access, in this case, the 'in' port, defined by typename Switch_defs::in.
        bag_port_in = get_messages<typename Switch_defs::in_master>(mbs); // To retrieve the bag (return vector message(in this case get messages of port in_source<OperatorLocation_t>) for us).
        //std::cout<<"size: "<<bag_port_in.size()<<"\n";
        
        uint32_t slot_id{0}; // for now
        for (auto const& mess : bag_port_in) {       // Add all messages to respective buffer   
            MessageBuffer_t& buffer = port_buffers_[mess.id_];
            buffer.messages.emplace_back(mess.id_, slot_id);
        }

        if (!state.transmitting_) {                 // Activate newly queued buffers            
            for (auto const& mess : bag_port_in)                
                port_buffers_[mess.id_].active = true;
            send();
        } 
        else {
            if (e <= prox_time_) {  
                prox_time_ -= e;    // Time left
            }
        }

        //std::cout<<"Prox time: "<<prox_time_<<"\n";
    }

    // cconfluence transition
    void confluence_transition(TIME e, typename make_message_bags<input_ports>::type mbs) { // mbs = std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
        // Default definition
        internal_transition();
        external_transition(TIME(), std::move(mbs)); // move(std::tuple<message_bag<Ps>...> / Ps = ports 'in').
    }

    // output function
    typename make_message_bags<output_ports>::type output() const 
    {
        // make_message_bags<>: is a template data type that the simulator needs (found in <cadmium/modeling/message_bag.hpp>).
        // Is instantiated as output_ports to   d efine the output bag.
        typename make_message_bags<output_ports>::type bags; // Therefore, bags is a tuple whose elements are the message bags available on the different output ports.
        //vector<OperatorLocation_t> bag_port_out0, bag_port_out1, bag_port_out2;

        for (auto& [id_node, buffer] : port_buffers_)
        {
            if (buffer.active){
                switch (id_node)
                {
                case 0:
                    get_messages<typename Switch_defs::out_0>(bags).push_back(*buffer.messages.begin());
                    buffer.messages.erase(buffer.messages.begin());
                    break;
                case 1:
                    get_messages<typename Switch_defs::out_1>(bags).push_back(*buffer.messages.begin());
                    buffer.messages.erase(buffer.messages.begin());
                    break;
                case 2:
                    get_messages<typename Switch_defs::out_2>(bags).push_back(*buffer.messages.begin());
                    buffer.messages.erase(buffer.messages.begin());
                    break;
                default:
                    break;
                }
                buffer.active = false; // Set to inactive
            }
        }

        //get_messages<typename Switch_defs::out_0>(bags) = bag_port_out0;
        //get_messages<typename Switch_defs::out_1>(bags) = bag_port_out1;
        //get_messages<typename Switch_defs::out_2>(bags) = bag_port_out2;

        return bags;
    }

    // time_advance function:  if we are transmitting_, the time advance is 3 seconds. If we do not transmit, the model passivates.
    TIME time_advance() const 
    {
        if (state.transmitting_) return prox_time_; // Lapse: hrs::mins:secs:mills:(micrs)::nns:pcs::fms
        else                     return numeric_limits<TIME>::infinity();
    }

    // Once all the DEVS functions are defined, we specify how we want to output the state of the model in the state log.
    // In this case, we only display two of the state variables: index and transmitting_.
    // That sentence typename Switch_t<TIME>::state_typ means that we are accessing the structure state_type inside the template class Switch_t<TIME>.
    // We need to declare the operator using the keyword 'friend's to specify that the function can access the private members of the structure state_type.
    friend ostringstream& operator<<(ostringstream& os, const typename Switch_t<TIME>::state_type& i) { // State log
        os << "transmitting: " << i.transmitting_; 
        return os;
    }

private:

    void send() noexcept 
    {
        int lapse { static_cast<int>(Random_t::poisson(mean_)) };
        send_time_ = TIME{0,0,0,0,1};
        prox_time_ = send_time_;
        state.transmitting_ = true;
    }
};

#endif // _SWITCH_HPP__