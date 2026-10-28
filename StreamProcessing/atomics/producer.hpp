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

    #if PROD_MOD
    using const_iter = typename std::vector<std::pair<TIME, double>>::const_iterator;
    #else
    using const_iter = typename std::vector<std::pair<uint32_t, double>>::const_iterator;
    #endif

    MLogger_t<TIME>&            metricLogger_;
    myrandom::Uniform_t<double> uni_distr_           {0.0, 1.0};

    std::vector<std::pair<uint32_t, double>> const& 
                                workloads_by_req_;
    std::vector<std::pair<TIME, double>> const&     
                                workloads_by_time_;

    Message_t  current_mssg_          {++this->state}; // Begin in 1.
    TIME       arrival_time_          {0};
    TIME       current_time_          {0};
    const_iter current_workload_;
    const_iter next_workload_;
    uint32_t   next_reqs_to_complete_ {};
    bool       generating_            {true};
    TIME       step_time_             {5e11}; //  0.5 sec
    TIME       time_to_capture_       {step_time_};

    // Exponential distribution
    [[nodiscard]] double 
    expo_distr(double rd, double lambda) const noexcept { return -(1/lambda)*std::log(1-rd); }

public:

    uint32_t last_requirements_{};

    [[nodiscard]] static constexpr TIME to_second(TIME const& time)
    {
        return time * 1e-12; // ps -> sec
    }

    Producer_t() {};

    Producer_t(MLogger_t<TIME>& mlogger)
    : 
     metricLogger_      {mlogger},
     workloads_by_req_  {mlogger.getClusterCFG().workloads_by_req_},
     workloads_by_time_ {mlogger.getClusterCFG().workloads_by_time_}
    {
        // Init current rate.
        #if PROD_MOD 
            current_workload_ = begin(workloads_by_time_); 
        #else
            current_workload_      = begin(workloads_by_req_);
            next_reqs_to_complete_ = (*current_workload_).first; // Set the first requeriments to complete.
        #endif
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

    #if PROD_MOD // Producer has 1 or more rates with time point to change the next rate.
    void internal_transition()
    {   
        // Inspect next.
        this->next_workload_ = this->current_workload_;
        ++next_workload_; 

        // Should be changed to the following rate?
        if (current_time_ >= next_workload_->first)
        {   
            // Is the final rate?
            if (next_workload_->second == 0) 
            {
                // Get the min next time from the other models.
                TIME min_advance_time { this->min_advance_time_in_atomic_models() };

                // All models has finished? Terminate too.
                if (min_advance_time == numeric_limits<TIME>::infinity())
                {
                    // This is the way to set the final workload.
                    this->last_requirements_ = this->state;
                    //std::cout<<"time(out): "<<current_time_<<", rate: "<<current_workload_->second<<'\n'; 
                    // Passivate
                    generating_ = false;
                    return;
                }

                // Move forward in time to continue capturing metrics.
                this->current_time_ += min_advance_time;
                this->arrival_time_ = min_advance_time;
                this->current_mssg_ = 0; // Set to zero to notify the master node that these are not requirements.

                #if LOG_MOD // Dynamic mod.
                    captureMetrics();
                #endif
                return;
            }
            
            current_workload_ = next_workload_; // Pass to next rate
            this->metricLogger_.getClusterCFG().nextWorkload(); // Update!
            //std::cout<<"time: "<<current_time_<<", rate: "<<current_workload_->second<<'\n'; 
        }
        
        // Generate time
        TIME lapse_ps {};
        do {
            lapse_ps = expo_distr(uni_distr_.generate(), current_workload_->second);
        } while (lapse_ps < 0);
        
        this->arrival_time_  = lapse_ps;
        this->current_time_ += this->arrival_time_;
        this->current_mssg_  = ++this->state;

        #if LOG_MOD // Dynamic mod.
            captureMetrics();
        #endif
    }
    #else // The producer has 1 or more rates with their quantity of requirements to produce.
    void internal_transition()
    {   
        // Inspect next.
        this->next_workload_ = this->current_workload_;
        ++next_workload_; 

        if (this->state >= this->next_reqs_to_complete_)
        {
            if (next_workload_ == end(this->workloads_by_req_)) // Have all the requirements for the final rate been met?
            {
                // Get the min next time from the other models.
                TIME min_advance_time { this->min_advance_time_in_atomic_models() };

                // All models has finished? Terminate too.
                if (min_advance_time == numeric_limits<TIME>::infinity())
                {
                    // This is the way to set the final workload.
                    this->last_requirements_ = this->state;
                    // Passivate.
                    generating_ = false;
                    return;
                }

                // Move forward in time to continue capturing metrics.
                this->current_time_ += min_advance_time;
                this->arrival_time_ = min_advance_time;
                this->current_mssg_ = 0; // Set to zero to notify the master node that these are not requirements.

                #if LOG_MOD // Dynamic mod.
                    captureMetrics();
                #endif
                return;
            }
            
            current_workload_ = next_workload_; // Pass to next rate.
            next_reqs_to_complete_ += (*current_workload_).first; // Pass next requirements to complete.
            this->metricLogger_.getClusterCFG().nextWorkload(); // Update!
        }

        // Generate time.
        TIME lapse_ps {};
        do {
            lapse_ps = expo_distr(uni_distr_.generate(), current_workload_->second);
        } while (lapse_ps < 0);
        
        this->arrival_time_  = lapse_ps;
        this->current_time_ += this->arrival_time_;
        this->current_mssg_  = ++this->state;

        #if LOG_MOD // Dynamic mod.
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
            uint32_t recs_out_accum                  = this->metricLogger_.getClusterCFG().operProps_[source_oper_id].records_out_accum_;

            metricLogger_.captureMetrics(to_second(this->current_time_), recs_out_accum);
            this->time_to_capture_ += this->step_time_;
        }
    }
};

} // namespace streeamprcss

#endif // _PRODUCER_HPP__
