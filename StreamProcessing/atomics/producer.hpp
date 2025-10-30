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
#include<fstream>
#include<string_view>

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

    uint32_t requeriments_{};
    double   rate_{};

    std::map<TIME, double>* arrivalRates_{nullptr};
    typename std::map<TIME, double>::iterator current_rate_;
    typename std::map<TIME, double>::iterator next_rate_;
    bool generating_ {true};

    std::ofstream log_rate;

    // Exponential distribution
    [[nodiscard]] double expo_distr(double rd, double lambda) const noexcept {   
        return -(1/lambda)*std::log(1-rd);
    }

public:

    Producer_t() {};

    Producer_t(uint32_t req, double rate, std::string_view path_to_log) 
    : requeriments_{req}, rate_{rate}, log_rate(path_to_log.data())
    {
        log_rate<<current_time_<<" "<<rate_<<"\n";
        std::cout<<"time: "<<current_time_<<" lambda: "<<rate_<<"\n";
    };

    Producer_t(std::map<TIME, double>& ar, std::string_view path_to_log)
    : basic_models::pdevs::generator<Message_t, TIME>{}, gen_{rd_()}, uni_distr_{0, 1}, arrivalRates_{&ar}, log_rate(path_to_log.data())
    {
        current_rate_ = begin(*arrivalRates_); // Init current rate.
        log_rate<<current_time_<<" "<<current_rate_->second<<"\n";
        std::cout<<"time: "<<current_time_<<" lambda: "<<current_rate_->second<<"\n";
    }

    TIME period() const override // time between consecutive messages
    {
        if (generating_) return arrival_time_;
        return numeric_limits<TIME>::infinity();
    }

    Message_t output_message() const override // message to be output
    {   
        //static uint32_t id_node {0};
        //++id_node;
        //if (id_node == 3) id_node = 0;

        return {this->state};
    }

    void internal_transition()
    {   
        /*next_rate_ = current_rate_;
        ++next_rate_; // inspect next

        // Should be changed to the following rate?
        if (current_time_ >= next_rate_->first)
        {   
            if (next_rate_->second == 0) { // Is the final rate?
                generating_ = false;
                log_rate<<current_time_<<" "<<0<<"\n";
                return;
            }
            current_rate_ = next_rate_; // Pass to next rate
            log_rate<<current_time_<<" "<<current_rate_->second<<"\n";
            std::cout<<"time: "<<current_time_<<" lambda: "<<current_rate_->second<<"\n";
        }
        int lapse { static_cast<int>(std::round(expo_distr(uni_distr_(gen_), current_rate_->second))) };
        int lapse_us {lapse};
        int lapse_hr  = lapse_us / 3'600'000'000;
        lapse_us     %= 3'600'000'000;
        int lapse_min = lapse_us / 60'000'000;
        lapse_us     %= 60'000'000;
        int lapse_s   = lapse_us / 1'000'000;
        lapse_us     %= 1'000'000;
        int lapse_ms  = lapse_us / 1'000;
        lapse_us     %= 1'000;

        //std::cout<<"lapse: "<<lapse<<"\n";
        //std::cout<<"hr: "<<lapse_hr<<" min: "<<lapse_min<<" s: "<<lapse_s<<" ms: "<<lapse_ms<<" us: "<<lapse_us<<"\n";
        arrival_time_ = {lapse_hr,lapse_min,lapse_s,lapse_ms,lapse_us}; // hrs::mins:secs:mills:(micrs)::nns:pcs::fms
        current_time_ += arrival_time_;

        ++this->state;*/

        if (this->state >= this->requeriments_)
        {
            generating_ = false;
            log_rate<<current_time_<<" "<<0<<"\n";
            return;
        }

        int lapse { static_cast<int>(std::round(expo_distr(uni_distr_(gen_), this->rate_))) };
        int lapse_us {lapse};
        int lapse_hr  = lapse_us / 3'600'000'000;
        lapse_us     %= 3'600'000'000;
        int lapse_min = lapse_us / 60'000'000;
        lapse_us     %= 60'000'000;
        int lapse_s   = lapse_us / 1'000'000;
        lapse_us     %= 1'000'000;
        int lapse_ms  = lapse_us / 1'000;
        lapse_us     %= 1'000;

        //std::cout<<"lapse: "<<lapse<<"\n";
        //std::cout<<"hr: "<<lapse_hr<<" min: "<<lapse_min<<" s: "<<lapse_s<<" ms: "<<lapse_ms<<" us: "<<lapse_us<<"\n";
        arrival_time_ = {lapse_hr,lapse_min,lapse_s,lapse_ms,lapse_us}; // hrs::mins:secs:mills:(micrs)::nns:pcs::fms
        current_time_ += arrival_time_;

        ++this->state;
    }

};

#endif // _PRODUCER_HPP__
