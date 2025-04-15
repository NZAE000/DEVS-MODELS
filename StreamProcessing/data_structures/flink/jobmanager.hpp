/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Jobmanager definition
*/
#pragma once
#include "../cluster_config.hpp"
#include "resourcemanager.hpp"
#include "jobmaster.hpp"

// Cadmium
#include <cadmium/modeling/dynamic_model.hpp>
#include <cadmium/modeling/dynamic_model_translator.hpp>
using namespace cadmium;
using namespace std;

namespace FLINK {


struct JobManager_t {

    explicit JobManager_t(ClusterConfig_t const& c_cgf)
    : cluster_cfg_{c_cgf} , jobMaster_{cluster_cfg_.topology_}, resourceMan_{}
    {
        std::srand(std::time(nullptr)); // Set seed.
    }

// Methods
    void deployJob(std::vector<shared_ptr<dynamic::modeling::model>>&)                                noexcept;
    [[nodiscard]] OperatorLocation_t           const& getOperLocationLessload(operId_t const&)  const noexcept;
    [[nodiscard]] std::vector<operId_t const*> const& getOperatorDestinations(operId_t const&)  const noexcept;
    [[nodiscard]] double getTimeExecution(operId_t const&)                                      const noexcept;

    //ClusterConfig_t const& getClusterCfg() const noexcept { return cluster_cfg_; }
    [[nodiscard]] operId_t const& firstOperator()                const noexcept;
    [[nodiscard]] bool            lastOperator(operId_t const&)  const noexcept;

private:
    ClusterConfig_t const& cluster_cfg_;

// Two principal components
    JobMaster_t         jobMaster_;
    ResourceManager_t   resourceMan_;
};

} // namespace FLINK