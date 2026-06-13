#include "metriclogger.hpp"
#include <iomanip>
#include <fstream>
//#include <iostream>

namespace streamprcss {
    namespace mylogger {

    template<typename TIME>
    MetricLogger_t<TIME>::
    MetricLogger_t(ClusterConfig_t const& ccfg) 
    : cluster_cfg_{ccfg} 
    {
        // Producer has 1 or more rates with time point to change theb next rate.
        #if PROD_MOD
        for (auto const& [_, rate] : this->cluster_cfg_.arrivalRates_) // Reserve possible quantity of metrics
        {
            if (!rate) continue;
            // Reserve sytem metrics.
            sysmetrics_t& sys_metrics = this->system_metrics_[rate];
            sys_metrics.reserve(MAX_NUM_METRICS_);

            // Reserve operator metrics.
            uint32_t n_oper { this->cluster_cfg_.N_OPERATORS_ };
            this->oper_metrics_.resize(n_oper);
            for (operId_t oper_id=0; oper_id < n_oper; ++oper_id)
            {  
                opermetrics_t& oper_metrics = this->oper_metrics_[oper_id][rate];
                oper_metrics.reserve(MAX_NUM_METRICS_);
            }
            this->captures_[rate] = 0; // Set captures.
        }
        #else // Producer has only 1 rate and stop when n requeriments are finished.
        // Reserve sytem metrics.
        double rate { this->cluster_cfg_.rate_};
        sysmetrics_t& sys_metrics = this->system_metrics_[rate];
        sys_metrics.reserve(MAX_NUM_METRICS_);
        
        // Reserve operator metrics.
        uint32_t n_oper { this->cluster_cfg_.N_OPERATORS_ };
        this->oper_metrics_.resize(n_oper);
        for (operId_t oper_id=0; oper_id < n_oper; ++oper_id)
        {  
            opermetrics_t& oper_metrics = this->oper_metrics_[oper_id][rate];
            oper_metrics.reserve(MAX_NUM_METRICS_);
        }
        this->captures_[rate] = 0; // Set captures.
        #endif
    }

    template<typename TIME>
    void MetricLogger_t<TIME>:: 
    captureMetrics(double rate, TIME elapsed_time, std::size_t procss_req) noexcept
    {
        // Add system metrics
        sysmetrics_t& sys_metrics = this->system_metrics_[rate];
        double        throughput  { procss_req / elapsed_time };
        sys_metrics.emplace_back(procss_req, elapsed_time, throughput);

        // Add operator metrics
        uint32_t n_oper { this->cluster_cfg_.N_OPERATORS_ };
        for (operId_t oper_id=0; oper_id < n_oper; ++oper_id)
        {  
            auto const&  props       { this->cluster_cfg_.operProps_[oper_id] };
            double       busy_time   { props.busy_time_accum_ / props.replication_ };
            double       utilization { busy_time / elapsed_time };

            opermetrics_t& oper_metrics = this->oper_metrics_[oper_id][rate];
            oper_metrics.emplace_back(props.replication_, 0, props.sent_records_accum_, props.busy_time_accum_, busy_time, utilization);
        }
        ++this->captures_[rate];
    }

    template<typename TIME>
    void MetricLogger_t<TIME>::
    printMetrics() const noexcept
    {
        /********** PRINT METRIC RESULTS ****************/
        std::string const& app_name  { this->cluster_cfg_.app_name_ };
        uint32_t           n_nodes   = this->cluster_cfg_.n_nodes_;
        uint32_t           n_cores   = this->cluster_cfg_.n_cores_;
        uint32_t           p_level   = this->cluster_cfg_.operProps_[this->cluster_cfg_.begin_op_].replication_; // Assume all operators have same replication level.

        // Print cluster config /////////////////////////////
        std::cout
            << "\nAPP: "     << app_name
            << "\tNodes: "   << n_nodes
            << "\tCores: "   << n_cores
            << "\tP_level: " << p_level
            << "\n\n";

        // Print system metrics ////////////////////////////
        for (auto const& [rate, sys_metrics] : this->system_metrics_)
        {
            std::cout <<"------------------- Rate: "<< static_cast<uint32_t>(rate * PS_TO_S_) << " (req/s) ------------------\n\n";
            std::cout << std::left
            << std::setw(20) << "Procesed reqs"
            << std::setw(20) << "Time (s)"
            << std::setw(20) << "Throughput (req/s)"
            << '\n';
            for (auto const& sysmetric : sys_metrics)
            {
                std::cout << std::left             
                << std::setw(20) << sysmetric.processed_req_
                << std::setw(20) << sysmetric.elapsed_time_
                << std::setw(20) << sysmetric.throughput_
                << '\n';
            } 
            std::cout << '\n';
        }   

        // Print operator metrics //////////////////////////

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
        uint32_t n_oper { this->cluster_cfg_.N_OPERATORS_ };
        for (auto const& [rate, captures] : this->captures_)
        {
            std::cout <<"------------------- Rate: "<< static_cast<uint32_t>(rate * PS_TO_S_) << " (req/s) ------------------\n\n";
            std::cout << std::left
            << std::setw(25) << "Operator"
            << std::setw(5)  << "P"
            //<< std::setw(15) << "RecordsSend"
            << std::setw(15) << "AccumBusyTime"
            << std::setw(15) << "BusyTime"
            << std::setw(15) << "Utilization"
            << '\n';
            for (uint32_t i=0; i < captures; ++i){
                for (operId_t oper_id=0; oper_id < n_oper; ++oper_id)
                { 
                    opermetrics_t const& oper_metrics = this->oper_metrics_[oper_id].find(rate)->second;
                    std::cout << std::left
                    << std::setw(25) << this->cluster_cfg_.operProps_[oper_id].name_
                    << std::setw(5)  << oper_metrics[i].p_level_
                    //<< std::setw(15) << oper_metrics[i].sent_records_accum_
                    << std::setw(15) << oper_metrics[i].accum_busy_time_
                    << std::setw(15) << oper_metrics[i].busy_time_
                    << std::setw(15) << oper_metrics[i].utilization_ << '\n';
                } 
                std::cout << '\n';
            }
        }
    }

    #if LOG_MOD
    template<typename TIME>
    void MetricLogger_t<TIME>::
    logDynamicMetrics() const noexcept
    {
        std::string const& app_name  { this->cluster_cfg_.app_name_ };
        uint32_t           n_nodes   = this->cluster_cfg_.n_nodes_;
        uint32_t           n_cores   = this->cluster_cfg_.n_cores_;
        uint32_t           p_level   = this->cluster_cfg_.operProps_[this->cluster_cfg_.begin_op_].replication_; // Assume all operators have same replication level.
        
        // Paths.
        std::string file_throughput { DYNAMIC_THROUGHPUT_BASE_PATH_ + app_name + "-" + std::to_string(n_nodes) + "-" + std::to_string(n_cores) + "-" 
                            + std::to_string(p_level) + ".txt" };

        std::string file_utilization { DYNAMIC_UTILIZATION_BASE_PATH_ + app_name + "-" + std::to_string(n_nodes) + "-" + std::to_string(n_cores) + "-" 
                        + std::to_string(p_level) + ".txt" };
        
        // Writters     .               
        std::ofstream out_throughput_result(file_throughput, std::ios::trunc);
        std::ofstream out_utilization_result(file_utilization, std::ios::trunc);

        // Log system metrics /////////////////////////////////////////////////////////////////
        for (auto const& [rate, sys_metrics] : this->system_metrics_)
        {
            out_throughput_result << static_cast<uint32_t>(rate * PS_TO_S_)  <<':'; // req/ps to res/s.
            for (auto const& sysmetric : sys_metrics) 
            {
                out_throughput_result << sysmetric.elapsed_time_ <<','<< sysmetric.throughput_<<' ';
            }
            out_throughput_result << '\n';
        }
        
        // Log operator metrics /////////////////////////////////////////////////////////////////
        // First, log rates horizontally.
        for (auto const& [rate, _] : this->captures_) out_utilization_result << static_cast<uint32_t>(rate * PS_TO_S_)  <<' ';
        out_utilization_result << '\n';

        // Then, all utilizations for each rate.        
        uint32_t n_oper { this->cluster_cfg_.N_OPERATORS_ };
        for (operId_t oper_id=0; oper_id < n_oper; ++oper_id)
        { 
            auto const& rate_opermetrics { this->oper_metrics_[oper_id] };
            out_utilization_result << this->cluster_cfg_.operProps_[oper_id].name_ <<':';
            for (auto const& [rate, oper_metrics] : rate_opermetrics)
            {
                out_utilization_result <<'[';
                for (auto const& oper_metric : oper_metrics) 
                {
                    out_utilization_result << oper_metric.utilization_<<' ';
                }
                out_utilization_result <<']';
            }
            out_utilization_result << '\n';
        }
    }

    #else
    template<typename TIME>
    void MetricLogger_t<TIME>::
    logMetrics() const noexcept
    {
        std::string const& app_name  { this->cluster_cfg_.app_name_ };
        uint32_t           n_nodes   = this->cluster_cfg_.n_nodes_;
        uint32_t           n_cores   = this->cluster_cfg_.n_cores_;
        uint32_t           p_level   = this->cluster_cfg_.operProps_[this->cluster_cfg_.begin_op_].replication_; // Assume all operators have same replication level.
        
        // Paths
        std::string file_throughput  {};
        std::string file_utilization {};
        
        // NOTE: Iterate only once!
        for (auto const& [rate, captures] : this->captures_) {
            for (uint32_t i=0; i < captures; ++i)
            {
                sysmetrics_t const& sys_metrics  { this->system_metrics_.find(rate)->second  };
                std::size_t         total_reqs   { sys_metrics[i].processed_req_             }; 
                uint32_t            a_rate       { static_cast<uint32_t>(rate * PS_TO_S_)     };  // req/ps to res/s.
                
                // Paths.
                file_throughput  = TERMINATED_THROUGHPUT_BASE_PATH_ + app_name + "-" + std::to_string(n_nodes) + "-" + std::to_string(n_cores) + "-" 
                                + std::to_string(p_level) + "-" + std::to_string(total_reqs) + "-" + std::to_string(a_rate) + ".txt";

                file_utilization = TERMINATED_UTILIZATION_BASE_PATH_ + app_name + "-" + std::to_string(n_nodes) + "-" + std::to_string(n_cores) + "-" 
                            + std::to_string(p_level) + "-" + std::to_string(total_reqs) + "-" + std::to_string(a_rate) + ".txt";

                // Wrtters.
                std::ofstream out_throughput_result(file_throughput, std::ios::app);
                std::ofstream out_utilization_result(file_utilization, std::ios::app);

                // Log system metrics.
                out_throughput_result << sys_metrics[i].elapsed_time_ <<' '<< sys_metrics[i].throughput_<<'\n';

                // Log operator metrics.
                uint32_t n_oper { this->cluster_cfg_.N_OPERATORS_ };
                for (operId_t oper_id=0; oper_id < n_oper; ++oper_id)
                { 
                    opermetrics_t const& oper_metrics = this->oper_metrics_[oper_id].find(rate)->second;
                    out_utilization_result << this->cluster_cfg_.operProps_[oper_id].name_ <<':'<< oper_metrics[i].utilization_<<';';
                } 
                out_utilization_result << '\n';
            }
        }
    }
    #endif

    } // namespace mylogger
} // namespace streamprcss