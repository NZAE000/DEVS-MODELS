/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Jobmaster definition
*/
#pragma once
#include <map>
#include <vector>
#include <string>
#include "typealiases.hpp"
#include "../clusterconfig.hpp"
#include "../operatorlocation.hpp"


namespace streamprcss {
    namespace flink {

    struct JobMaster_t {

        explicit JobMaster_t(ClusterConfig_t const& c_cfg, std::size_t locs_capacity) 
        : job_graph_{c_cfg.topology_} 
        {
            this->oper_locations_.resize(c_cfg.N_OPERATORS_);
            for (auto& locations : this->oper_locations_)
                locations.reserve(locs_capacity);
        }

    //Methods
                                                        void addLocation(operId_t const, nodeId_t, slotId_t)  noexcept;
        [[nodiscard]] std::vector<OperatorLocation_t> const& getLocations(operId_t const)               const noexcept;
        [[nodiscard]] std::vector<operId_t> const&           operatorDestinations(operId_t const)       const noexcept;

    private:
        std::vector<std::vector<operId_t>> const&    job_graph_;
        std::vector<std::vector<OperatorLocation_t>> oper_locations_ {};

    };

    } // namespace flink 
} // namespace streamprcss