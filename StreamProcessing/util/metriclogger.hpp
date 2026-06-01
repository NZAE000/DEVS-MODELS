#pragma once
#include<data_structures/cluster_config.hpp>

namespace streamprcss {
    namespace mylogger {

    template<typename TIME>
    struct MetricLogger_t {

        struct SystemMetric_t {
            uint32_t     arrival_rate_  {};
            std::size_t  processed_req_ {};
            double       elapsed_time_  {};
            double       throughput_    {};
        };

        using opername_t = ClusterConfig_t::operId_t;
        struct OperMetric_t {
            uint32_t     p_level_          {};
            std::size_t  recv_records_     {};
            std::size_t  sent_records_     {};
            double       accum_busy_time_  {};
            double       busy_time_        {};
            double       utilization_      {};
        };

        explicit MetricLogger_t(ClusterConfig_t&);

        auto const& getClusterCFG() const noexcept { return cluster_cfg_; }
        auto&       getClusterCFG()       noexcept { return cluster_cfg_; }

        void captureMetrics(double rate, TIME elapsed_t, std::size_t procss_req) noexcept;
        void printMetrics()                                                const noexcept;
        void logMetrics()                                                  const noexcept;

    private:
        ClusterConfig_t&                                       cluster_cfg_;
        std::vector<SystemMetric_t>                            system_metrics_{};
        std::map<opername_t const*, std::vector<OperMetric_t>> oper_metrics_  {};
        uint32_t                                               n_captures_{};

        inline static constexpr char const* THROUGHPUT_DIR  {"metrics/nexmark/throughput/simulated/"};
        inline static constexpr char const* UTILIZATION_DIR {"metrics/nexmark/utilization/simulated/"};
        inline static constexpr std::size_t MAX_NUM_METRICS {20};
    };

    } // namespace mylogger
} // namespace streamprcss