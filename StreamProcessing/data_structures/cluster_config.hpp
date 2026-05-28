/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Cluster config implementation
*/

#pragma once
#include<map>
#include<vector>
#include<string_view>
#include<string>
#include<fstream>
//#include<iostream>
#include<functional>
#include<cassert>
#include<memory>
#include <NDTime.hpp>


#include "../util/random.hpp"
#include "../input_data/hardware.hpp"


//Time class header
#include <NDTime.hpp> // NDTime is a C++ class that implements time operations and allows defining the time as in digital clock format (“hh:mm:ss:mss”) or as a list of integer elements ({ hh, mm, ss, mss})
using TIME = NDTime;


struct ConfigPath_t {
    static constexpr std::string_view topo_path     {"input_data/topology.txt"};
    static constexpr std::string_view oper_path     {"input_data/operator.txt"};
    static constexpr std::string_view hw_path       {"input_data/hardware.txt"};
    static constexpr std::string_view dg_path       {"input_data/degradation.txt"};
    static constexpr std::string_view iw_path       {"input_data/extraoccupation.txt"};
    static constexpr std::string_view arrival_path  {"input_data/arrival_rate.txt"};
    static constexpr std::string_view reqsRate_path {"input_data/reqsRate.txt"};
};

struct OperatorProperties_t {

    uint32_t                                replication_{};
    std::unique_ptr<myrandom::RandomBase_t> random_{};
    std::string                             ship_strategy_{};
    double                                  selectivity_{};
    uint32_t                                acumm_recordsSend_{};
    double                                  accum_busy_time_{}; // To calculate operator utilization.
    double                                  w_{};               // Weight to operator extra internal work.
    
    //std::function<double(void)> distribution{}; // Callback
};

struct ClusterConfig_t {

    using operId_t = std::string;

    explicit ClusterConfig_t()
    {
        initOperators(ConfigPath_t::oper_path); // It must inizialize first.
        initTopology(ConfigPath_t::topo_path);
        initHardware(ConfigPath_t::hw_path);
        initDegradationFactors(ConfigPath_t::dg_path);
        initWeightOperators(ConfigPath_t::iw_path);
        initRates(ConfigPath_t::arrival_path);
        initReqsRate(ConfigPath_t::reqsRate_path);
    }

// Data config
    std::map<operId_t, OperatorProperties_t>                operProps_{}; // Operator ids resource.
    std::map<operId_t const*, std::vector<operId_t const*>> topology_{};
    std::map<TIME, double>                                  arrivalRates_{};
    uint32_t requeriments_{}; double rate_{};

    double degradation_factor_{};                               // Degradation phenomenon factor (interference + saturation + inefficiency of parallelism).
    //double //gamma_{};                                            // Function to extra internal work (applied to the accumulation of busy operator time).

    operId_t const* begin_op{};
    std::vector<operId_t const*> end_ops{};

    uint32_t n_nodes_{};
    uint32_t n_cores_{};


    void accumBusyTime(operId_t const& operid, double time) noexcept
    {
        auto prop_it   = operProps_.find(operid);
        auto& operprop = prop_it->second;
        //double lamda {0.9}, beta{0.071001}; // p=2 -> l=0.9, 
        //auto extrawork = [&]() -> double { return 1 + lamda * (degradation_factor_ - 1) + beta * operprop.w_; };

        operprop.accum_busy_time_ += time * operprop.w_; //* ( 1 + lamda * (degradation_factor_ - 1) + beta * operprop.w_);//extrawork();
    }

private:

    void initOperators(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        std::string name{}, distr{}, strategy{};
        uint32_t oper_parallelism{};
        double selectivity{};

        std::string line{};
        while (std::getline(file, line)) 
        {    
            if (line.empty())  continue;      // Ignore empty lines.
            std::istringstream iss(line);
            iss>>name>>oper_parallelism>>distr;

            if (PARALLELISM_L > 1) oper_parallelism = PARALLELISM_L; // Priority.

            if (distr == "norm"){
                double param1{}, param2{};
                iss>>param1>>param2>>strategy>>selectivity;
                operProps_[name] = {oper_parallelism, std::make_unique<myrandom::Normal_t>(param1, param2), strategy, selectivity};
                
                //operProps_[name] = {oper_parallelism, [param1, param2](){
                //    return myrandom_t::normal(param1, param2);
                //}};
            }
            else if (distr == "fix"){
                double param{};
                iss>>param>>strategy>>selectivity;
                operProps_[name] = {oper_parallelism, std::make_unique<myrandom::Constant_t>(param), strategy, selectivity};

                //operProps_[name] = {oper_parallelism, [param](){
                //    return param;
                //}};
            }
            else if (distr == "expo"){
                double param{};
                iss>>param>>strategy>>selectivity;
                operProps_[name] = {oper_parallelism, std::make_unique<myrandom::Exponential_t>(param), strategy, selectivity};

                //operProps_[name] = {oper_parallelism, [param](){
                //    return myrandom_t::exponential(param);
                //}};
            }
            else if (distr == "lnorm"){
                double param1{}, param2{};
                iss>>param1>>param2>>strategy>>selectivity;
                operProps_[name] = {oper_parallelism, std::make_unique<myrandom::LogNormal_t>(param1, param2), strategy, selectivity};

                //operProps_[name] = {oper_parallelism, [param1, param2](){
                //    return myrandom_t::logNormal(param1, param2);
                //}};
            }
            else if (distr == "gamm"){
                double param1{}, param2{};
                iss>>param1>>param2>>strategy>>selectivity;
                operProps_[name] = {oper_parallelism, std::make_unique<myrandom::Gamma_t>(param1, param2), strategy, selectivity};

                //operProps_[name] = {oper_parallelism, [param1, param2](){
                //    return myrandom_t::gamma(param1, param2);
                //}};
            }
        }
    }

    void initTopology(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        std::string from{}, to{};
        uint32_t count_op{};

        std::string line{};
        while (std::getline(file, line)) 
        {    
            if (line.empty())  continue;      // Ignore empty lines.
            std::istringstream iss(line);
            iss>>from>>to;

            auto& from_ref = operProps_.find(from)->first;
            auto& to_ref   = operProps_.find(to)->first;

            topology_[&from_ref].emplace_back(&to_ref);
            //std::cout<<"From: "<<from_ref<<" To: "<<to_ref<<'\n';

            // Store first operator.
            if (!count_op) { 
                begin_op = &operProps_.find(from)->first; ++count_op; 
            }
        }

        // Store all end operators
        for (auto const& [_, all_to] : topology_){
            std::for_each(all_to.begin(), all_to.end(), [&](auto const* to)
            {
                uint8_t final {1};
                for (auto const& [from, _] : topology_)
                    if (to == from) { final = 0; break; } // Then isn't final operator.
    
                if (final) this->end_ops.push_back(to);
            });
        }

        // Discard duplicated end operators.
        std::sort(end_ops.begin(), end_ops.end()); 
        auto last = std::unique(end_ops.begin(), end_ops.end()); 
        end_ops.erase(last, end_ops.end()); 

        //std::for_each(begin(topology_), end(topology_), [&](auto const& link){
        //    std::cout<<"from: "<<*link.first<<" to: "<< link.second.size()<<"\n";
        //    for (auto const to : link.second) std::cout<<"\t"<<*to<<"\n";
        //});
        //
        //std::cout<<"finals: \n";
        //for (auto const* final : end_ops) std::cout<<" \t"<<*final<<"\n";
    }

    void initHardware(std::string_view path) noexcept
    {
        //std::ifstream file(path.data());
        //file>>n_cores_;
        n_nodes_ = N_NODES;
        n_cores_ = N_CORES;
        assert( n_nodes_ > 0 && "Invalid hardware parameter: n_nodes is 0" );
        assert( n_cores_ > 0 && "Invalid hardware parameter: n_cores is 0" );
    }

    void initDegradationFactors(std::string_view path) noexcept
    {
        double cpuu_{}, u_thr_{}, alpha_{}, u_sat_{}, b_{0.05}, e_{};
        std::ifstream file(path.data());
        file>>cpuu_>>u_thr_>>alpha_>>u_sat_>>e_;

        double interferency_   { (1 + alpha_ * std::max(0.0, cpuu_ - u_thr_)) };
        double saturation_     { (1 + b_     * std::max(0.0, cpuu_ - u_sat_)) };
        double p_inefficiency_ { 1 / e_ };

        degradation_factor_ = interferency_ * saturation_ * p_inefficiency_;
        //gamma_              = std::max(0.0, cpuu_ - u_thr_);
        //std::cout<<"cpuu: "<<cpuu_<<" u_thr: "<<u_thr_<<" alpha: "<<alpha_<<" u_sat: "<<u_sat_<<"\n";
        std::cout<<"deg: "<<degradation_factor_<<'\n';
    }

    void initWeightOperators(std::string_view path) noexcept 
    {
        std::ifstream file(path.data());
        std::string name{};
        double weight{};

        std::string line{};
        while (std::getline(file, line)) 
        {    
            if (line.empty())  continue;      // Ignore empty lines.
            std::istringstream iss(line);
            iss>>name>>weight;
            operProps_[name].w_ = weight;
        }
    }

    void initRates(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        TIME time {}; double rate{};

        while (!file.eof())
        {
            file>>time>>rate;
            arrivalRates_[time] = rate;
            //std::cout<<"time: "<<time<<" rate: "<<rate<<"\n";
        }
    }

    void initReqsRate(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        int requriments {}; double rate{};

        //while (!file.eof())
        //{
            file>>this->requeriments_>>this->rate_;
            
            //std::cout<<"requriments: "<<requeriments_<<" rate: "<<rate_<<"\n";
        //}
    }
};