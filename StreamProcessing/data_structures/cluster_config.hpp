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
#include<iostream>
#include<functional>
#include<cassert>


#include "../util/random.hpp"
#include "../input_data/hardware.hpp"


//Time class header
#include <NDTime.hpp> // NDTime is a C++ class that implements time operations and allows defining the time as in digital clock format (“hh:mm:ss:mss”) or as a list of integer elements ({ hh, mm, ss, mss})
using TIME = NDTime;


struct ConfigPath_t {
    static constexpr std::string_view topo_path    {"input_data/topology.txt"};
    static constexpr std::string_view oper_path    {"input_data/operator.txt"};
    static constexpr std::string_view hw_path      {"input_data/hardware.txt"};
    static constexpr std::string_view arrival_path {"input_data/arrival_rate.txt"};
};

struct OperatorProperties_t {
    uint32_t replication{};
    std::function<double(void)> distribution{}; // Callback
};

struct ClusterConfig_t {

    using operId_t = std::string;

    explicit ClusterConfig_t()
    {
        initOperators(ConfigPath_t::oper_path); // It must inizialize first.
        initTopology(ConfigPath_t::topo_path);
        initHardware(ConfigPath_t::hw_path);
        initRates(ConfigPath_t::arrival_path);
    }

// Data config
    std::map<operId_t, OperatorProperties_t>                operProps_{}; // Operator ids resource.
    std::map<operId_t const*, std::vector<operId_t const*>> topology_{};
    std::map<TIME, double>                                  arrivalRates_{};
    operId_t const* begin_op{};
    std::vector<operId_t const*> end_ops{};
    uint32_t n_nodes_{};
    uint32_t n_cores_ {};

private:

    void initOperators(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        std::string name{}, distr{};
        uint32_t replica{};
        uint32_t count{};

        while (!file.eof())
        {
            file>>name>>replica>>distr;

            if (distr == "fix"){
                double param{};
                file>>param;

                operProps_[name] = {replica, [param](){
                    return param;
                }};
            }
            else if (distr == "norm"){
                double param1{}, param2{};
                file>>param1>>param2;

                operProps_[name] = {replica, [param1, param2](){
                    return Random_t::normal(param1, param2);
                }};
            }
            else if (distr == "expo"){
                double param{};
                file>>param;
                operProps_[name] = {replica, [param](){
                    return Random_t::exponential(param);
                }};
            }

            // Store first operator.
            if (count == 0) { 
                begin_op = &operProps_.find(name)->first; ++count; 
            }
        }
    }

    void initTopology(std::string_view path) noexcept
    {
        std::ifstream file(path.data());
        std::string from{}, to{};
        while (!file.eof())
        {
            file>>from>>to;
            auto& from_ref = operProps_.find(from)->first;
            auto& to_ref   = operProps_.find(to)->first;

            topology_[&from_ref].emplace_back(&to_ref);
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
};