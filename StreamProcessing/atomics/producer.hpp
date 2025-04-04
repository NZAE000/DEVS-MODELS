/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Productor implementation
*/

#ifndef _PRODUCER_HPP__
#define _PRODUCER_HPP__

#include <cadmium/modeling/ports.hpp>
#include <cadmium/modeling/message_bag.hpp> // Used to declare a bag of messages for input or output port.

#include <limits>
#include <assert.h>
#include <string>
#include <random>
#include <iostream>

#include "../data_structures/message.hpp"
#include <cadmium/basic_model/pdevs/generator.hpp>

using namespace cadmium;
using namespace std;



// Productor is an atomic generator
template<typename TIME>
class Producer_t : public basic_models::pdevs::generator<Message_t, TIME> { 

    static constexpr uint32_t PROB_MIN {0};
    static constexpr uint32_t PROB_MAX {1};

    // Create a random number generator object based on Mersenne Twister
    std::random_device rd_;                              // A seed source for the random number engine. Get a seed from the system's random device
    std::mt19937      gen_;                              // Mersenne_twister_engine(2**19,937) generator, seeded with rd(). Initialize the generator with the device seed
    std::uniform_real_distribution<double> uni_distr_;   // Define a range for uniform random numbers

    TIME current_time_ {0};
    TIME arrival_time_ {0};

    std::map<TIME, double>& arrivalRates_;
    typename std::map<TIME, double>::iterator current_rate_;
    typename std::map<TIME, double>::iterator next_rate_;
    bool generating_ {true};

    // Exponential distribution
    [[nodiscard]] double expo_distr(double rd, double lambda) const noexcept {   
        return -(1/lambda)*std::log(1-rd);
    }

public:

    Producer_t() {};
    Producer_t(std::map<TIME, double>& ar)
    : basic_models::pdevs::generator<Message_t, TIME>{}, gen_{rd_()}, uni_distr_{0, 1}, arrivalRates_{ar}
    {
        current_rate_ = begin(arrivalRates_);
        std::cout<<"time: "<<current_time_<<" lambda: "<<current_rate_->second<<"\n";

    }

    TIME period() const override // time between consecutive messages
    {
        if (generating_) return arrival_time_;
        return numeric_limits<TIME>::infinity();
    }

    Message_t output_message() const override // message to be output
    {   
        static uint32_t id_node {0};
        ++id_node;
        if (id_node == 3) id_node = 0;

        return {id_node};
    }

    void internal_transition()
    {   
        next_rate_ = current_rate_;
        ++next_rate_; // inspect next

        // Should be changed to the following rate?
        if (current_time_ >= next_rate_->first)
        {   
            if (next_rate_->second == 0) { // Is the final rate?
                generating_ = false;
                return;
            }
            current_rate_ = next_rate_; // Pass to next rate
            std::cout<<"time: "<<current_time_<<" lambda: "<<current_rate_->second<<"\n";
        }

        int lapse { static_cast<int>(std::round(expo_distr(uni_distr_(gen_), current_rate_->second))) };
        arrival_time_ = {0,0,0,0,lapse}; // hrs::mins:secs:mills:(micrs)::nns:pcs::fms
        current_time_ += arrival_time_;

        ++this->state;
    }

};

#endif // _PRODUCER_HPP__
