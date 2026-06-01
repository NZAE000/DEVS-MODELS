#include "metriclogger.hpp"
#include<iostream>
#include<iomanip>
#include<fstream>

namespace streamprcss {
    namespace mylogger {

    template<typename TIME>
    MetricLogger_t<TIME>::
    MetricLogger_t(ClusterConfig_t& ccfg) 
    : cluster_cfg_{ccfg} 
    {
        system_metrics_.reserve(MAX_NUM_METRICS);
        for (auto const& [oper_name, _] : cluster_cfg_.operProps_) 
        {
            auto& oper_metrics = oper_metrics_[&oper_name];
            oper_metrics.reserve(MAX_NUM_METRICS);
        }
    }

    template<typename TIME>
    void MetricLogger_t<TIME>:: 
    captureMetrics(double rate, TIME elapsed_time, std::size_t procss_req) noexcept
    {
        // Add system metrics
        uint32_t arrival_rate { static_cast<uint32_t>(rate * 1e12) }; // req/ps to res/s.
        double   throughput   { procss_req / elapsed_time          };
        this->system_metrics_.emplace_back(arrival_rate, procss_req, elapsed_time, throughput);

        // Add operator metrics
        for (auto const& [oper_name, props] : cluster_cfg_.operProps_) 
        {
            double busy_time   { props.busy_time_accum_ / props.replication_ };
            double utilization { busy_time / elapsed_time };
            auto& oper_metrics = oper_metrics_[&oper_name];
            oper_metrics.emplace_back(props.replication_, 0, props.sent_records_accum_, props.busy_time_accum_, busy_time, utilization);
        }
        ++this->n_captures_;
    }

    template<typename TIME>
    void MetricLogger_t<TIME>::
    printMetrics() const noexcept
    {
        /********** PRINT METRIC RESULTS ****************/
        std::string const& app_name  { cluster_cfg_.app_name };
        uint32_t           n_nodes   = cluster_cfg_.n_nodes_;
        uint32_t           n_cores   = cluster_cfg_.n_cores_;
        uint32_t           p_level   = cluster_cfg_.operProps_.find(*cluster_cfg_.begin_op)->second.replication_; // Assume all operators have same replication level.
        //uint32_t           arrival_rate = static_cast<uint32_t>(cluster_cfg_.rate_ * 1e12); // req/ps to res/s.

        // Print cluster config /////////////////////////////
        std::cout << std::left
            << std::setw(8) << "\nAPP"
            << std::setw(8) << "Nodes"
            << std::setw(8) << "Cores"
            << std::setw(8) << "P level"
            << '\n';

        std::cout << std::left
            << std::setw(8) << app_name
            << std::setw(8) << n_nodes
            << std::setw(8) << n_cores
            << std::setw(8) << p_level
            << "\n\n";

        // Print system metrics ////////////////////////////
        std::cout << std::left
            << std::setw(25) << "Arrival rate (req/s)"
            << std::setw(20) << "Procesed reqs"
            << std::setw(20) << "Time (s)"
            << std::setw(20) << "Throughput (req/s)"
            << '\n';

        for (auto const& sysmetric : this->system_metrics_)
        {
            std::cout << std::left
            << std::setw(25) << sysmetric.arrival_rate_
            << std::setw(20) << sysmetric.processed_req_
            << std::setw(20) << sysmetric.elapsed_time_
            << std::setw(20) << sysmetric.throughput_
            << '\n';
        } std::cout << '\n';


        // Print operator metrics //////////////////////////
        std::cout << std::left
            << std::setw(25) << "Operator"
            << std::setw(5)  << "P"
            //<< std::setw(15) << "RecordsSend"
            << std::setw(15) << "AccumBusyTime"
            << std::setw(15) << "BusyTime"
            << std::setw(15) << "Utilization"
            << '\n';

        // First, read the operators names to establish order.
        //std::ifstream             operator_file(ConfigPath_t::oper_path.data());
        //std::vector<std::string>  oper_names{};
        //std::string               line{};
        //
        //while (std::getline(operator_file, line)) 
        //{    
        //    if (line.empty()) continue;      // Ignore empty lines.
        //    std::istringstream iss(line);
        //    std::string        oper_name;
        //    iss >> oper_name;
        //    oper_names.emplace_back(oper_name);
        //}

        for (uint32_t i=0; i < this->n_captures_; ++i)
        {
            for (auto const& [oper_name, metrics] : this->oper_metrics_) 
            {
                std::cout << std::left
                << std::setw(25) << *oper_name
                << std::setw(5)  << metrics[i].p_level_
                //<< std::setw(15) << metrics[i].sent_records_accum_
                << std::setw(15) << metrics[i].accum_busy_time_
                << std::setw(15) << metrics[i].busy_time_
                << std::setw(15) << metrics[i].utilization_ << '\n';
            } std::cout << '\n';
        }
    }

    template<typename TIME>
    void MetricLogger_t<TIME>::
    logMetrics() const noexcept
    {
        std::string const& app_name  { cluster_cfg_.app_name };
        uint32_t           n_nodes   = cluster_cfg_.n_nodes_;
        uint32_t           n_cores   = cluster_cfg_.n_cores_;
        uint32_t           p_level   = cluster_cfg_.operProps_.find(*cluster_cfg_.begin_op)->second.replication_; // Assume all operators have same replication level.
        
        // Paths
        std::string file_throughput  {};
        std::string file_utilization {};
        
        for (uint32_t i=0; i < this->n_captures_; ++i)
        { 
            SystemMetric_t const& sysmetrics { this->system_metrics_[i]  }; // Get the unique.
            std::size_t total_reqs           { sysmetrics.processed_req_ }; 
            uint32_t arrival_rate            { sysmetrics.arrival_rate_  };  // req/ps to res/s.

            file_throughput  = THROUGHPUT_DIR + app_name + "-throughput-" + std::to_string(n_nodes) + "-" + std::to_string(n_cores) + "-" 
                            + std::to_string(p_level) + "-" + std::to_string(total_reqs) + "-" + std::to_string(arrival_rate) + ".txt";

            file_utilization = UTILIZATION_DIR + app_name + "-utilization-" + std::to_string(n_nodes) + "-" + std::to_string(n_cores) + "-" 
                        + std::to_string(p_level) + "-" + std::to_string(total_reqs) + "-" + std::to_string(arrival_rate) + ".txt";

            // Log system metrics in file.
            std::ofstream out_throughput_result(file_throughput, std::ios::app);
            out_throughput_result << sysmetrics.elapsed_time_ <<' '<< sysmetrics.throughput_<<'\n';

            // Log operator metrics in file.
            std::ofstream out_utilization_result(file_utilization, std::ios::app);
            for (auto const& [oper_name, metrics] : this->oper_metrics_) 
            {
                out_utilization_result << *oper_name <<':'<< metrics[i].utilization_<<';';
            } 
            out_utilization_result << '\n';
        }
    }

    } // namespace mylogger
} // namespace streamprcss