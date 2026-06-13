/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Cluster config implementation
*/

#pragma once
#include <map>
#include <vector>
#include <string_view>
#include <string>
#include <fstream>
#include <functional>
#include <cassert>
#include <memory>
#include "flink/typealiases.hpp"
#include "../util/random.hpp"
#include "../input_data/hardware.hpp"
//#include <iostream>

using TIME = streamprcss::flink::TIME;


struct ConfigPath_t {
    static constexpr std::string_view topo_path       {"input_data/topology.txt"};
    static constexpr std::string_view oper_path       {"input_data/operator.txt"};
    static constexpr std::string_view hw_path         {"input_data/hardware.txt"};
    static constexpr std::string_view workload_path   {"input_data/workload.txt"};
    static constexpr std::string_view arate_path      {"input_data/arrivalrates.txt"};
    static constexpr std::string_view degrad_path     {"input_data/degradation.txt"};
    static constexpr std::string_view extraoccup_path {"input_data/extraoccupation.txt"};
};

struct OperatorProperties_t {

    std::string                             name_               {};
    uint32_t                                replication_        {};
    std::unique_ptr
    <myrandom::RandomBase_t<TIME>>          random_time_        {};
    std::string                             ship_strategy_      {};
    double                                  selectivity_        {};
    uint32_t                                sent_records_accum_ {};
    double                                  busy_time_accum_    {};     // To calculate operator utilization.
    double                                  extra_occup_factor_ {};     // Extra internal occupation factor.
};

struct ClusterConfig_t {

    using operId_t = streamprcss::flink::operId_t;

    explicit ClusterConfig_t(std::string_view app_n) : app_name_{app_n}
    {
        initOperators(ConfigPath_t::oper_path); // It must inizialize first.
        initTopology(ConfigPath_t::topo_path);
        initHardware(ConfigPath_t::hw_path);
        initWorkload(ConfigPath_t::workload_path);
        initRates(ConfigPath_t::arate_path);
        initDegradFactor(ConfigPath_t::degrad_path);
        initExtraOccupFactors(ConfigPath_t::extraoccup_path);
    }

// Data config
    std::string                         app_name_           {};
    std::vector<OperatorProperties_t>   operProps_          {};
    std::vector<std::vector<operId_t>>  topology_           {};
    operId_t                            begin_op_           {};
    std::vector<operId_t>               end_ops_            {};
    std::map<TIME, double>              arrivalRates_       {};
    uint32_t                            requeriments_       {}; 
    double                              rate_               {};
    uint32_t                            n_nodes_            {};
    uint32_t                            n_cores_            {};
    double                              degradation_factor_ {};  // Degradation phenomenon factor (interference + saturation + inefficiency of parallelism).
    inline static operId_t              N_OPERATORS_        {0};

    void accumBusyTime(operId_t const operid, double time) noexcept
    {
        auto& operprop = operProps_[operid];
        operprop.busy_time_accum_ += time * operprop.extra_occup_factor_; //* ( 1 + lamda * (degradation_factor_ - 1) + beta * operprop.w_);//extrawork();
    }

    void accumSentRecords(operId_t const operid, uint32_t n_rec) noexcept
    {
        auto& operprop = operProps_[operid];
        operprop.sent_records_accum_ += n_rec;
    }

private:
    std::map<std::string, operId_t> oper_ids_ {};

    void initOperators(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        std::string name{}, distr{}, strategy{};
        uint32_t oper_parallelism  {};
        double   selectivity       {};

        // First, count lines to know operator count.
        std::string line        {};
        uint32_t    n_operators {};
        while (std::getline(file, line)){
            if (line.empty())  continue;
            ++n_operators;
        }

        // Then, reserve.
        //std::cout<<"n_ops: "<<n_operators <<'\n';
        this->operProps_.reserve(n_operators);

        // Restet.
        file.clear();
        file.seekg(0, std::ios::beg);

        // Read operators properties.
        while (std::getline(file, line)) 
        {    
            if (line.empty())  continue;      // Ignore empty lines.
            std::istringstream iss(line);
            iss >> name >> oper_parallelism >> distr;

            if (PARALLELISM_L > 1) oper_parallelism = PARALLELISM_L; // Priority.

            if (distr == "norm"){
                double param1{}, param2{};
                iss >> param1 >> param2 >> strategy >> selectivity;
                operProps_.emplace_back(name, oper_parallelism, std::make_unique<myrandom::Normal_t<TIME>>(param1, param2), strategy, selectivity);
            }
            else if (distr == "fix"){
                double param{};
                iss >> param >> strategy >> selectivity;
                operProps_.emplace_back(name, oper_parallelism, std::make_unique<myrandom::Constant_t<TIME>>(param), strategy, selectivity);
            }
            else if (distr == "expo"){
                double param{};
                iss >> param >> strategy >> selectivity;
                operProps_.emplace_back(name, oper_parallelism, std::make_unique<myrandom::Exponential_t<TIME>>(param), strategy, selectivity);
            }
            else if (distr == "lnorm"){
                double param1{}, param2{};
                iss >> param1 >> param2 >> strategy >> selectivity;
                operProps_.emplace_back(name, oper_parallelism, std::make_unique<myrandom::Lognormal_t<TIME>>(param1, param2), strategy, selectivity);
            }
            else if (distr == "gamm"){
                double param1{}, param2{};
                iss >> param1 >> param2 >> strategy >> selectivity;
                operProps_.emplace_back(name, oper_parallelism, std::make_unique<myrandom::Gamma_t<TIME>>(param1, param2), strategy, selectivity);
            }

            this->oper_ids_[operProps_[N_OPERATORS_].name_] = N_OPERATORS_; // Store name reerences.
            ++N_OPERATORS_;
        }

        //for (auto const& prop : this->operProps_) std::cout<<prop.name_<<'\n';
    }

    void initTopology(std::string_view path) noexcept
    {
        this->topology_.resize(N_OPERATORS_ - 1); // The final operator has no follow-up.
        std::ifstream file(path.data());
        std::string from  {}, to {};
        uint32_t count_op {};

        std::string line{};
        while (std::getline(file, line)) 
        {    
            if (line.empty())  continue;      // Ignore empty lines.
            std::istringstream iss(line);
            iss >> from >> to;

            operId_t from_id = this->oper_ids_.find(from)->second;
            operId_t to_id   = this->oper_ids_.find(to)->second;
            topology_[from_id].emplace_back(to_id);
            //std::cout<<"From: "<<from_id<<" To: "<<to_id<<'\n';

            // Store first operator.
            if (!count_op) { 
                begin_op_ = this->oper_ids_.find(from)->second; ++count_op; 
            } 
        }

        // Store end operators.
        std::string const* oper_to {nullptr};
        for (auto const& all_to : topology_){
            std::for_each(all_to.begin(), all_to.end(), [&](operId_t const to)
            {
                uint8_t final {1};
                for (operId_t from=0; from < this->topology_.size(); ++from)
                    if (to == from) { final = 0; break; } // Then isn't final operator.
    
                if (final) this->end_ops_.push_back(to);
            });
        }

        //std::cout<<"ends: ";
        //for (auto const& end : this->end_ops_) std::cout<<end<<' '; 
        //std::cout<<" \n";

        // Discard duplicated end operators.
        std::sort(end_ops_.begin(), end_ops_.end()); 
        auto last = std::unique(end_ops_.begin(), end_ops_.end()); 
        end_ops_.erase(last, end_ops_.end()); 

        //std::for_each(begin(topology_), end(topology_), [&](auto const& link){
        //    std::cout<<"from: "<<*link.first<<" to: "<< link.second.size()<<"\n";
        //    for (auto const to : link.second) std::cout<<"\t"<<*to<<"\n";
        //});
        //
        //std::cout<<"finals: \n";
        //for (auto const* final : end_ops_) std::cout<<" \t"<<*final<<"\n";
    }

    void initHardware(std::string_view path) noexcept
    {
        n_nodes_ = N_NODES;
        n_cores_ = N_CORES;
        assert( n_nodes_ > 0 && "Invalid hardware parameter: n_nodes is 0" );
        assert( n_cores_ > 0 && "Invalid hardware parameter: n_cores is 0" );
    }

    void initDegradFactor(std::string_view path) noexcept
    {
        double cpuu_{}, u_thr_{}, alpha_{}, u_sat_{}, b_{0.05}, e_{};
        std::ifstream file(path.data());
        file >> cpuu_ >> u_thr_ >> alpha_ >> u_sat_ >> e_;

        double interferency_   { (1 + alpha_ * std::max(0.0, cpuu_ - u_thr_)) };
        double saturation_     { (1 + b_     * std::max(0.0, cpuu_ - u_sat_)) };
        double p_inefficiency_ { 1 / e_ };

        degradation_factor_ = interferency_ * saturation_ * p_inefficiency_;
    }

    void initExtraOccupFactors(std::string_view path) noexcept 
    {
        std::ifstream file(path.data());
        std::string   name{};
        double        extra_occ_factor{};

        std::string line{};
        while (std::getline(file, line)) 
        {    
            if (line.empty())  continue;      // Ignore empty lines.
            std::istringstream iss(line);
            iss >> name >> extra_occ_factor;

            operId_t op_id = this->oper_ids_.find(name)->second;
            operProps_[op_id].extra_occup_factor_ = extra_occ_factor;
        }
    }

    void initRates(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        TIME time {}; double rate{};

        while (!file.eof())
        {
            file >> time >> rate;
            arrivalRates_[time] = rate;
            //std::cout<<"time: "<<time<<" rate: "<<rate<<"\n";
        }
    }

    void initWorkload(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        int requriments {}; double rate{};

        file >> this->requeriments_ >> this->rate_;
        //std::cout<<"requriments: "<<requeriments_<<" rate: "<<rate_<<"\n";
    }
};