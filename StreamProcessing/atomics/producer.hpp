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
#include <cadmium/modeling/dynamic_model.hpp>
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

    MLogger_t<TIME>&                metricLogger_;
    myrandom::Uniform_t<double>     uni_distr_           {0.0, 1.0};
    uint32_t                        requeriments_        {};
    double                          rate_                {};
    std::map<TIME, double> const&   arrivalRates_;
    Message_t                       current_mssg_        {};
    TIME                            arrival_time_        {0};
    TIME                            current_time_        {0};
    const_iter                      current_rate_;
    const_iter                      next_rate_;
    bool                            generating_          {true};
    TIME                            step_time_           {5e11}; //  0.5 sec
    TIME                            time_to_capture_     {step_time_};

    // Exponential distribution
    [[nodiscard]] double 
    expo_distr(double rd, double lambda) const noexcept { return -(1/lambda)*std::log(1-rd); }

public:

    [[nodiscard]] static constexpr TIME to_second(TIME const& time)
    {
        return time * 1e-12;
    }

    Producer_t() {};

    Producer_t(MLogger_t<TIME>& mlogger)
    : 
     metricLogger_ {mlogger},
     requeriments_ {mlogger.getClusterCFG().requeriments_}, 
     rate_         {mlogger.getClusterCFG().rate_},
     arrivalRates_ {mlogger.getClusterCFG().arrivalRates_}
    {
        current_rate_ = begin(arrivalRates_); // Init current rate.
        ++this->state;                        // Begin in 1.
        //std::cout<<"time: "<<this->current_time_<<" lambda: "<<current_rate_->second<<"\n";
    }

    TIME period() const override // Time between consecutive messages.
    {
        if (generating_) return this->arrival_time_;
        return numeric_limits<TIME>::infinity();
    }

    Message_t output_message() const override // Message to be output.
    {   
        return {this->current_mssg_};
    }

    #if PROD_MOD // Producer has 1 or more rates with time point to change theb next rate.
    void internal_transition()
    {   
        // Inspect next.
        next_rate_ = current_rate_;
        ++next_rate_; 

        // Should be changed to the following rate?
        if (this->current_time_ >= next_rate_->first)
        {   
            // Is the final rate?
            if (next_rate_->second == 0) 
            {
                // This is the way to set the final workload.
                metricLogger_.getClusterCFG().rate_         = current_rate_->second;
                metricLogger_.getClusterCFG().requeriments_ = this->state;
                
                // Passivate
                generating_ = false;
                return;
            }
             
            #if LOG_MOD
            metricLogger_.captureMetrics(current_rate_->second, this->current_time_, to_second(this->current_time_), this->state); // Capture metrics!
            #endif

            current_rate_ = next_rate_; // Pass to next rate
            //std::cout<<"time: "<<this->current_time_<<" lambda: "<<current_rate_->second<<"\n";
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
        this->arrival_time_  = lapse_ps;//{lapse_hr, lapse_min, lapse_s, lapse_ms, lapse_us, lapse_ns, lapse_ps}; // hrs::mins:secs:mills:micrs::nns:(pcs)::fms
        this->current_time_ += this->arrival_time_;
        this->current_mssg_  = ++this->state;

        #if LOG_MOD
        if (this->state % 100 == 0)
            metricLogger_.captureMetrics(current_rate_->second, this->current_time_, to_second(this->current_time_), this->state);
        #endif
    }
    #else // Producer has only 1 rate and stop when n requeriments are finished.
    void internal_transition()
    {   
        if (this->state >= this->requeriments_)  // Complete all the requirements? Keep capturing metrics.
        {
            // Get the min next time from the other models.
            TIME min_advance_time { this->min_advance_time_in_atomic_models() };

            // All models has finished? Terminate too.
            if (min_advance_time == numeric_limits<TIME>::infinity()){
                generating_ = false;
                return;
            }

            // Move forward in time to continue capturing metrics.
            this->current_time_ += min_advance_time;
            this->arrival_time_ = min_advance_time;
            this->current_mssg_ = 0; // Set to zero to notify the master node that these are not requirements.
        }
        else {
            // Generate time.
            TIME lapse_ps {};
            do {
                lapse_ps = expo_distr(uni_distr_.generate(), this->rate_);
            } while (lapse_ps < 0);
            
            this->arrival_time_  = lapse_ps;
            this->current_time_ += this->arrival_time_;
            this->current_mssg_  = ++this->state;
        }

        #if LOG_MOD
            captureMetrics();
        #endif
    }
    #endif


    void receiveModels(cadmium::dynamic::modeling::Models const& models)
    {
        using model_t      = std::shared_ptr<cadmium::dynamic::modeling::model>;
        using atomic_abs_t = cadmium::dynamic::modeling::atomic_abstract<TIME>;

        // Reserve!
        abstract_atomics_.reserve(models.size());
        advance_times.resize(models.size());

        // Store atomics models references.
        for (model_t const& model : models)
            abstract_atomics_.emplace_back(dynamic_cast<atomic_abs_t const*>(model.get()));
    }

private:

    using atomic_abs_t = cadmium::dynamic::modeling::atomic_abstract<TIME>;
    
    std::vector<atomic_abs_t const*> abstract_atomics_ {};
    std::vector<TIME>                advance_times     {};

    // Retrive the minimal advance time from atomics models.
    TIME min_advance_time_in_atomic_models() 
    {
        std::transform(
                this->abstract_atomics_.cbegin(),
                this->abstract_atomics_.cend(),
                this->advance_times.begin(),
                [] (const auto& atomic) -> TIME { return atomic->time_advance(); }
        );
        return *std::min_element(advance_times.begin(), advance_times.end());
    }

    // Capture metrics each time period (s).
    void captureMetrics() noexcept
    {
        if (this->current_time_ >= this->time_to_capture_) // Capture?
        {
            ClusterConfig_t::operId_t source_oper_id = this->metricLogger_.getClusterCFG().begin_op_;
            uint32_t sent_rec_accum                  = this->metricLogger_.getClusterCFG().operProps_[source_oper_id].sent_records_accum_;

            metricLogger_.captureMetrics(this->rate_, to_second(this->current_time_), sent_rec_accum);
            this->time_to_capture_ += this->step_time_;
        }
    }
};

} // namespace streeamprcss

#endif // _PRODUCER_HPP__

