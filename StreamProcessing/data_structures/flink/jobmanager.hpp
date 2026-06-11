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
#include <ctime>

namespace FLINK {


struct JobManager_t {

    explicit JobManager_t(ClusterConfig_t& c_cgf)
    : cluster_cfg_{c_cgf}, jobMaster_{}, resourceMan_{c_cgf.n_nodes_}
    {
        std::srand(std::time(nullptr)); // Set seed.

        free_locs_.reserve(LOCS_CAPACITY_);
        locs_shorter_queue_.reserve(LOCS_CAPACITY_);
    }

// Methods
    template<typename Callable>
    void deployJob(Callable&& createNodes) noexcept;

    [[nodiscard]] OperatorLocation_t            getOperLocationLessload(operId_t const)  const noexcept;
    [[nodiscard]] std::vector<operId_t> const&  getOperatorDestinations(operId_t const)  const noexcept;
    [[nodiscard]] OperatorProperties_t const&   getOperatorProperties(operId_t const)    const noexcept;
    [[nodiscard]] OperatorProperties_t&         getOperatorProperties(operId_t const)          noexcept;
    [[nodiscard]] operId_t                      getFirstOperator()                       const noexcept;
    [[nodiscard]] bool                          lastOperator(operId_t const)             const noexcept;
    [[nodiscard]] double                        getTimeExecution(operId_t const)         const noexcept;
    [[nodiscard]] double                        getDegradationFactor()                   const noexcept;
                  void                          accumBusyTime(operId_t const, double)          noexcept;
                  void                          accumSentRecords(operId_t const, uint32_t)     noexcept;

private:

// Cfg access.
    ClusterConfig_t&   cluster_cfg_;

// Two principal components.
    JobMaster_t        jobMaster_{};
    ResourceManager_t  resourceMan_{1};

// Container with frecuently use.
    mutable std::vector<OperatorLocation_t const*>  free_locs_          {};
    mutable std::vector<OperatorLocation_t const*>  locs_shorter_queue_ {};
    inline static constexpr std::size_t             LOCS_CAPACITY_      {64};
};

} // namespace FLINK