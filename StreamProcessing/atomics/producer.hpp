/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Productor implementation
*/

#ifndef _PRODUCER_HPP__
#define _PRODUCER_HPP__

#ifndef PROD_MOD
#define PROD_MOD 0 // Define producer transsmition method: 1 has only 1 rate and stop when n requeriments are finished, or 0 has 1 or more rates with time point to change theb next rate.
#endif

#include <cadmium/modeling/ports.hpp>
#include <cadmium/modeling/message_bag.hpp> // Used to declare a bag of messages for input or output port.
#include <limits>
#include <assert.h>
#include <string>
#include <random>
#include <iostream>
#include <data_structures/message.hpp>
#include <util/random.hpp>
#include <util/metriclogger.hpp>
#include <cadmium/basic_model/pdevs/generator.hpp>
#include <fstream>
#include <string_view>

using namespace cadmium;
using namespace std;

namespace streamprcss {

template<typename T>
using MLogger_t = streamprcss::mylogger::MetricLogger_t<T>;

// Productor is an atomic generator
template<typename TIME>
class Producer_t : public basic_models::pdevs::generator<Message_t, TIME> { 

    // Create a random number generator object based on Mersenne Twister
    //std::random_device rd_;                              // A seed source for the random number engine. Get a seed from the system's random device
    //std::mt19937      gen_;                              // Mersenne_twister_engine(2**19,937) generator, seeded with rd(). Initialize the generator with the device seed
    //std::uniform_real_distribution<double> uni_distr_;   // Define a range for uniform random numbers

    using const_iter = typename std::map<TIME, double>::const_iterator;

    MLogger_t<double>&             metricLogger_;
    myrandom::Uniform_t            uni_distr_       {0, 1};
    uint32_t                       requeriments_    {};
    double                         rate_            {};
    std::map<TIME, double> const&  arrivalRates_;
    TIME                           arrival_time_    {0};
    TIME                           current_time_    {0};
    const_iter                     current_rate_;
    const_iter                     next_rate_;
    bool                           generating_      {true};
    std::ofstream                  log_rate;
    uint32_t                       accum_sent_rec_source_{};
    uint32_t                       reqs_to_captute_ {1};

    // Exponential distribution
    [[nodiscard]] double 
    expo_distr(double rd, double lambda) const noexcept { return -(1/lambda)*std::log(1-rd); }

    //double to_second(TIME const& time)
    //{
    //    
    //    return static_cast<double>(
    //        time.getHours()         *  3600 +
    //        time.getMinutes()       *    60 +
    //        time.getSeconds()       *     1 +
    //        time.getMilliseconds()  *  1e-3 +
    //        time.getMicroseconds()  *  1e-6 +
    //        time.getNanoseconds()   *  1e-9 +
    //        time.getPicoseconds()   * 1e-12 +
    //        time.getFemtoseconds()  * 1e-15
    //    );
    //}

public:

    [[nodiscard]] static constexpr double to_second(TIME const& time)
    {
        return time * 1e-12;
    }

    Producer_t() {};

    Producer_t(MLogger_t<double>& mlogger, std::string_view path_to_log)
    : 
     metricLogger_ {mlogger},
     requeriments_ {mlogger.getClusterCFG().requeriments_}, 
     rate_         {mlogger.getClusterCFG().rate_},
     arrivalRates_ {mlogger.getClusterCFG().arrivalRates_}, 
     log_rate      (path_to_log.data())
    {
        current_rate_ = begin(arrivalRates_); // Init current rate.
        log_rate<<current_time_<<" "<<current_rate_->second<<"\n";
        //std::cout<<"time: "<<current_time_<<" lambda: "<<current_rate_->second<<"\n";
    }

    TIME period() const override // Time between consecutive messages.
    {
        if (generating_) return arrival_time_;
        return numeric_limits<TIME>::infinity();
    }

    Message_t output_message() const override // Message to be output.
    {   
        return {this->state};
    }

    #if PROD_MOD // Producer has 1 or more rates with time point to change theb next rate.
    void internal_transition()
    {   
        // Inspect next.
        next_rate_ = current_rate_;
        ++next_rate_; 

        // Should be changed to the following rate?
        if (current_time_ >= next_rate_->first)
        {   
            // Is the final rate?
            if (next_rate_->second == 0) 
            {
                // This is the way to set the final workload.
                metricLogger_.getClusterCFG().rate_         = current_rate_->second;
                metricLogger_.getClusterCFG().requeriments_ = this->state;
                
                // Passivate
                generating_ = false;
                log_rate<<current_time_<<" "<<0<<"\n";
                return;
            }
             
            #if LOG_MOD
            metricLogger_.captureMetrics(current_rate_->second, current_time_, to_second(current_time_), this->state); // Capture metrics!
            #endif

            current_rate_ = next_rate_; // Pass to next rate
            log_rate<<current_time_<<" "<<current_rate_->second<<"\n";
            //std::cout<<"time: "<<current_time_<<" lambda: "<<current_rate_->second<<"\n";
        }
        
        // Generate time
        TIME lapse_ps {};
        do {
            //lapse_ps = static_cast<uint32_t>(std::round(expo_distr(uni_distr_.generate(), current_rate_->second)));
            lapse_ps = expo_distr(uni_distr_.generate(), current_rate_->second);
        } while (lapse_ps < 0);
        
        // Descompose time
        //int lapse_hr = lapse_ps / 3'600'000'000'000'000;  // 3.6e15
        //lapse_ps    %=  3'600'000'000'000'000;
//
        //int lapse_min = lapse_ps / 60'000'000'000'000;    // 6e13
        //lapse_ps     %= 60'000'000'000'000;
//
        //int lapse_s = lapse_ps / 1'000'000'000'000;       // 1e12
        //lapse_ps   %= 1'000'000'000'000;
//
        //int lapse_ms = lapse_ps / 1'000'000'000;          // 1e9
        //lapse_ps    %= 1'000'000'000;
//
        //int lapse_us = lapse_ps / 1'000'000;              // 1e6
        //lapse_ps    %= 1'000'000;
//
        //int lapse_ns = lapse_ps / 1'000;                  // 1e3
        //lapse_ps    %= 1'000;

        //std::cout<<"lapse: "<<lapse<<"\n";
        //std::cout<<"prod: hr: "<<lapse_hr<<" min: "<<lapse_min<<" s: "<<lapse_s<<" ms: "<<lapse_ms<<" us: "<<lapse_us<<" ns: "<<lapse_ns<<" ps: "<<lapse_ps<<"\n";
        arrival_time_ = lapse_ps;//{lapse_hr, lapse_min, lapse_s, lapse_ms, lapse_us, lapse_ns, lapse_ps}; // hrs::mins:secs:mills:micrs::nns:(pcs)::fms
        current_time_ += arrival_time_;

        ++this->state;

        #if LOG_MOD
        if (this->state % 100 == 0)
            metricLogger_.captureMetrics(current_rate_->second, current_time_, to_second(current_time_), this->state);
        #endif
    }
    #else // Producer has only 1 rate and stop when n requeriments are finished.
    void internal_transition()
    {   
        if (this->state >= this->requeriments_-1)
        {
            generating_ = false;
            log_rate<<current_time_<<" "<<0<<"\n";
            return;
        }

        // Generate time
        TIME lapse_ps {};
        do{
            //lapse_ps = static_cast<uint32_t>(std::round(expo_distr(uni_distr_.generate(), this->rate_)));
            lapse_ps = expo_distr(uni_distr_.generate(), this->rate_);
        } while (lapse_ps < 0);
        
        // Descompose time
        //int lapse_hr = lapse_ps / 3'600'000'000'000'000;  // 3.6e15
        //lapse_ps    %=  3'600'000'000'000'000;
//
        //int lapse_min = lapse_ps / 60'000'000'000'000;    // 6e13
        //lapse_ps     %= 60'000'000'000'000;
//
        //int lapse_s = lapse_ps / 1'000'000'000'000;       // 1e12
        //lapse_ps   %= 1'000'000'000'000;
//
        //int lapse_ms = lapse_ps / 1'000'000'000;          // 1e9
        //lapse_ps    %= 1'000'000'000;
//
        //int lapse_us = lapse_ps / 1'000'000;              // 1e6
        //lapse_ps    %= 1'000'000;
//
        //int lapse_ns = lapse_ps / 1'000;                  // 1e3
        //lapse_ps    %= 1'000;

        //std::cout<<"lapse: "<<lapse<<"\n";
        //std::cout<<"prod: hr: "<<lapse_hr<<" min: "<<lapse_min<<" s: "<<lapse_s<<" ms: "<<lapse_ms<<" us: "<<lapse_us<<" ns: "<<lapse_ns<<" ps: "<<lapse_ps<<"\n";
        //arrival_time_ = {lapse_hr,lapse_min,lapse_s,lapse_ms,lapse_us}; // hrs::mins:secs:mills:(micrs)::nns:pcs::fms
        arrival_time_ = lapse_ps;//{lapse_hr, lapse_min, lapse_s, lapse_ms, lapse_us, lapse_ns, lapse_ps}; // hrs::mins:secs:mills:micrs::nns:(pcs)::fms
        current_time_ += arrival_time_;

        ++this->state;
        
        #if LOG_MOD
        if (this->state % reqs_to_captute_ == 0)
        {
            ClusterConfig_t::operId_t source_oper_id = this->metricLogger_.getClusterCFG().begin_op_;
            uint32_t sent_rec_accum                  = this->metricLogger_.getClusterCFG().operProps_[source_oper_id].sent_records_accum_;
            //if (sent_rec_accum != this->accum_sent_rec_source_)
            //{
                this->accum_sent_rec_source_ = sent_rec_accum;
                metricLogger_.captureMetrics(this->rate_, to_second(current_time_), sent_rec_accum);

                if (this->state < 200) reqs_to_captute_ += 2;
                else                   reqs_to_captute_ += 500;
        }
        #endif
    }
    #endif
};

} // namespace streeamprcss

#endif // _PRODUCER_HPP__

