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
#include <boost/preprocessor/repetition/repeat.hpp>
#include <boost/preprocessor/repetition/enum.hpp>
#include <boost/preprocessor/cat.hpp>
#include <limits>
#include <assert.h>
#include <string>
#include <random>
#include <iostream>
#include <vector>

#include "../input_data/hardware.hpp"
#include "../data_structures/operator_location.hpp"
#include "../data_structures/message.hpp"
#include "../util/random.hpp"

using namespace cadmium;
using namespace std;

/*Call order: external, time_avance, output, internal*/


struct MessageBuffer_t {
    std::vector<OperatorLocation_t> messages{};
    bool active {false};
};


// Atomic model definition
template<typename TIME> 
class Switch_t { 

public:

    //Port definition (for now)
    //struct defs_inport {
    //    struct in_0  : public in_port<OperatorLocation_t> {}; 
    //    struct in_1  : public in_port<OperatorLocation_t> {}; 
    //    struct in_2  : public in_port<OperatorLocation_t> {};
    //    struct in_3  : public in_port<OperatorLocation_t> {};
    //    struct out_0 : public out_port<OperatorLocation_t> {};
    //    struct out_1 : public out_port<OperatorLocation_t> {};
    //    struct out_2 : public out_port<OperatorLocation_t> {};
    //    struct out_3 : public out_port<OperatorLocation_t> {};
    //};

    // ports definition: tuple for distintes types of messages
    // NOTA: The 'typename' specifies that Switch_defs::in and Switch_defs::out aredatatypesthatwilloverwritethetemplateclassinthesimulator
    //"typename" indicates that the expression that follows is a "data type" (not a specific object).
    //using input_ports  = tuple<typename defs_port::in_0,  typename defs_port::in_1,  typename defs_port::in_2,  typename defs_port::in_3>;
    //using output_ports = tuple<typename defs_port::out_0, typename defs_port::out_1, typename defs_port::out_2, typename defs_port::out_3>;

    // Metaprogramming at the preprocessing level with Boost Preprocessor.
    #define INPORT(z, n, _)  struct in_##n  : public in_port<OperatorLocation_t> {};
    #define OUTPORT(z, n, _) struct out_##n : public out_port<OperatorLocation_t> {};

    struct defs_port {
        BOOST_PP_REPEAT(N_NODES, INPORT, _)
        BOOST_PP_REPEAT(N_NODES, OUTPORT, _)
    };

    #define INPORT_TYPENAME(z, n, _)  typename defs_port::in_##n
    #define OUTPORT_TYPENAME(z, n, _) typename defs_port::out_##n

    using input_ports  = tuple<BOOST_PP_ENUM(N_NODES, INPORT_TYPENAME, _)>;
    using output_ports = tuple<BOOST_PP_ENUM(N_NODES, OUTPORT_TYPENAME, _)>;
    using nodeId_t     = uint32_t;

    
    // State definition (state variables of the Switch_t model)
    struct state_type {
        bool transmitting_{false};   // Used to define that the model has something to output
        mutable std::map<nodeId_t, MessageBuffer_t> port_buffers_{}; // node_id, buffer.
    };
    state_type state;

    TIME send_time_{};  // Time left until next departure
    int mean_ {10};

    // Default constructor
    Switch_t() noexcept {}

    // internal transition: model sets the state variable transmitting_ to false.
    void internal_transition() 
    {
        std::cout<<"[switch internal]\n";
        uint8_t pending_sends{0};

        for (auto & [_, buffer] : state.port_buffers_) { // Are there any pending messages in any of the output port buffers?
            if (!buffer.messages.empty()) { 
                buffer.active = true;
                ++pending_sends;
            }
        }
        if (!pending_sends) state.transmitting_ = false; // Are not there pending sends?
        else send();
    }

    // external transition. Params: the elapsed time (e) and a bag of message (mbs).
    // make_message_bags<>: is a template data type that the simulator needs (found in <cadmium/modeling/message_bag.hpp>)
    // (Here (in this model), mbs is a tuple of one bag: the message bag in port in. The messages inside the set of messages in the bag are stored in a C++ vector.)
    void external_transition(TIME e, typename make_message_bags<input_ports>::type mbs)  // std::tuple<message_bag<Ps>...> / Ps = ports 'in'.
    {
        // get_messages<>: to get the message bag from the port (in this case input port).
        // Uses a template parameter for the port we want to access, in this case, the 'in' port, defined by typename Switch_defs::in.
        //vector<OperatorLocation_t> bag_port_in;
        //bag_port_in = get_messages<typename Switch_defs::in_0>(mbs); // To retrieve the bag (return vector message(in this case get messages of port in_source<OperatorLocation_t>) for us).
        //std::cout<<"size: "<<bag_port_in.size()<<"\n";
        
        //vector<vector<OperatorLocation_t>> bags_port_in {
        //    get_messages<typename defs_port::in_0>(mbs),
        //    get_messages<typename defs_port::in_1>(mbs),
        //    get_messages<typename defs_port::in_2>(mbs),
        //    get_messages<typename defs_port::in_3>(mbs)
        //};

        // Metaprogramming at the preprocessing level with Boost Preprocessor.
        #define GET_MESSAGES_INPORT(z, n, _) get_messages<typename defs_port::in_##n>(mbs)
        vector<vector<OperatorLocation_t>> bags_port_in {
            BOOST_PP_ENUM(N_NODES, GET_MESSAGES_INPORT, _)
        };

        for (auto const& bag_port_in :  bags_port_in) { // Get each bag port int.
            for (auto const& mess : bag_port_in) {       // Add all messages to respective buffer.
                MessageBuffer_t& buffer = state.port_buffers_[mess.node_id];
                buffer.messages.emplace_back(mess.node_id, mess.slot_id);
            }
        }
        if (!state.transmitting_) {  // Activate newly queued buffers.
            for (auto const& bag_port_in : bags_port_in) {
                for (auto const& mess : bag_port_in) {
                    MessageBuffer_t& buffer = state.port_buffers_[mess.node_id];
                    if (!buffer.active) buffer.active = true;
                } 
            }              
            send();
        } 
        else send_time_ -= e;  // Minus time left (e = elapsed time value since last transition).

        std::cout<<"\n[switch external]: send time: "<<send_time_<<"\n";
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

        // Metaprogramming at the preprocessing level with Boost Preprocessor.
        #define GENERATE_CASE(z, n, _) \
            case n: \ 
            get_messages<typename defs_port::BOOST_PP_CAT(out_, n)>(bags).push_back(*buffer.messages.begin()); \
            buffer.messages.erase(buffer.messages.begin()); \
            break;

        for (auto& [id_node, buffer] : state.port_buffers_)
        {
            if (buffer.active){
                switch (id_node) // For now
                {
                BOOST_PP_REPEAT(N_NODES, GENERATE_CASE, _)
                default:
                    break;
                //case 0:
                //    get_messages<typename defs_port::out_0>(bags).push_back(*buffer.messages.begin()); // Get the first in line queue.
                //    buffer.messages.erase(buffer.messages.begin());
                //    break;
                //case 1:
                //    get_messages<typename defs_port::out_1>(bags).push_back(*buffer.messages.begin());
                //    buffer.messages.erase(buffer.messages.begin());
                //    break;
                //case 2:
                //    get_messages<typename defs_port::out_2>(bags).push_back(*buffer.messages.begin());
                //    buffer.messages.erase(buffer.messages.begin());
                //    break;
                //case 3:
                //    get_messages<typename defs_port::out_3>(bags).push_back(*buffer.messages.begin());
                //    buffer.messages.erase(buffer.messages.begin());
                //default:
                //    break;
                }
                buffer.active = false; // Set to inactive.
            }
        }

        std::cout<<"[switch output]\n";

        //get_messages<typename defs_port::out_0>(bags) = bag_port_out0;
        //get_messages<typename defs_port::out_1>(bags) = bag_port_out1;
        //get_messages<typename defs_port::out_2>(bags) = bag_port_out2;

        return bags;
    }

    // time_advance function:  if we are transmitting_, the time advance is 3 seconds. If we do not transmit, the model passivates.
    TIME time_advance() const 
    {
        if (state.transmitting_) return send_time_; // Lapse: hrs::mins:secs:mills:(micrs)::nns:pcs::fms
        else                     return numeric_limits<TIME>::infinity();
    }

    // Once all the DEVS functions are defined, we specify how we want to output the state of the model in the state log.
    // In this case, we only display two of the state variables: index and transmitting_.
    // That sentence typename Switch_t<TIME>::state_typ means that we are accessing the structure state_type inside the template class Switch_t<TIME>.
    // We need to declare the operator using the keyword 'friend's to specify that the function can access the private members of the structure state_type.
    friend ostringstream& operator<<(ostringstream& os, const typename Switch_t<TIME>::state_type& i) { // State log
        os << "transmitting: " << i.transmitting_;
        if (i.transmitting_)
        {
            os << " [ ";
            for (auto const& [node_id, buffer] : i.port_buffers_) {
                if (buffer.active){
                    os << "{"<<buffer.messages.at(0)<<"} ";
                }
            }
            os << "]";
        } 
        return os;
    }

private:

    void send() noexcept 
    {
        int lapse { static_cast<int>(Random_t::poisson(mean_)) }; // Poisson distribution send time.
        //std::cout<<"\nlapse:" << lapse;
        send_time_ = TIME{0,0,0,0,lapse}; // hrs::mins:secs:mills:micrs::nns:pcs::fms
        state.transmitting_ = true;
    }
};

#endif // _SWITCH_HPP__