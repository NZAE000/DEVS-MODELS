#pragma once
#include<data_structures/clusterconfig.hpp>

    /*
    I can capture metrics for differents ways:

        |                    λ                        | 
        |                   lapse                     |
        |                   reqs                      |
        |---------------------------------------------|
     begin sim                                    end sim

        |                   λ                         | 
        |  lapse1 lapse2 lapse3 lapse4 lapse5 lapseN  |
        |  reqs1  reqs2  reqs3  reqs4  reqs5  reqsN   |
        |---------------------------------------------|
     begin sim                                    end sim

        |      λ1    |    λ2    |    λ3   |    λN     | 
        |    lapse1  |  lapse2  |  lapse3 |  lapseN   |
        |    reqs1   |  reqs2   |  reqs3  |  reqsN    |
        |---------------------------------------------|
     begin sim                                     end sim

        
        |           λ1         |         λN           | 
        | lapse1 lapse2 lapseN | lapse1 lapse2 lapseN |
        | reqs1  reqs2  reqsN  | reqs1  reqs2  reqsN  |
        |---------------------------------------------|
     begin sim                                     end sim
    
    */

#ifndef APPLY_LOG
#define APPLY_LOG 1 // Log metrics in file (1) or not (0).
#endif

#ifndef LOG_MOD
#define LOG_MOD 0 // If metric logger is dynamic (1) (log during execution time) or only log when the execution is terminated (0).
#endif

namespace streamprcss {
    namespace mylogger {

    template<typename TIME>
    struct MetricLogger_t {

        using operId_t = ClusterConfig_t::operId_t;
        using rate_t   = double;

        struct SysMetric_t {
            std::size_t  processed_req_ {};
            double       elapsed_time_  {};
            double       throughput_    {};
        };
        using sysmetrics_t = std::vector<SysMetric_t>;

        struct OperMetric_t {
            uint32_t     p_level_          {};
            std::size_t  recv_records_     {};
            std::size_t  sent_records_     {};
            double       accum_busy_time_  {};
            double       busy_time_        {};
            double       utilization_      {};
        };
        using opermetrics_t = std::vector<OperMetric_t>;

        explicit MetricLogger_t(ClusterConfig_t const&);

        void captureMetrics(double rate, TIME elapsed_t, std::size_t procss_req) noexcept;
        void printMetrics()                                                const noexcept;

        #if LOG_MOD
        void logDynamicMetrics()                                           const noexcept;
        #else
        void logMetrics()                                                  const noexcept;
        #endif

        auto const& getClusterCFG() const noexcept { return cluster_cfg_; }
        auto&       getClusterCFG()       noexcept { return cluster_cfg_; }
         
    private:
        
        ClusterConfig_t const&                       cluster_cfg_;
        std::map<rate_t,   sysmetrics_t>             system_metrics_ {};
        std::vector<std::map<rate_t, opermetrics_t>> oper_metrics_   {};
        std::map<rate_t,   uint32_t>                 captures_       {};

        #if LOG_MOD
        inline static constexpr char const* DYNAMIC_THROUGHPUT_BASE_PATH_     {"metrics/nexmark/throughput/sim/dynamic/dynamic-throughput-sim-"};
        inline static constexpr char const* DYNAMIC_UTILIZATION_BASE_PATH_    {"metrics/nexmark/utilization/sim/dynamic/dynamic-utilization-sim-"};
        #else
        inline static constexpr char const* TERMINATED_THROUGHPUT_BASE_PATH_  {"metrics/nexmark/throughput/sim/terminated/terminated-throughput-sim-"};
        inline static constexpr char const* TERMINATED_UTILIZATION_BASE_PATH_ {"metrics/nexmark/utilization/sim/terminated/terminated-utilization-sim-"};
        #endif
        inline static constexpr std::size_t MAX_NUM_METRICS_ { 100000000 };
        inline static constexpr double      PS_TO_S_         { 1e12      };
    };

    } // namespace mylogger
} // namespace streamprcss