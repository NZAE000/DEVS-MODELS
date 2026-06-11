/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskslot definition
*/
#pragma once
#include "taskmanager.hpp"
#include "taskslot.hpp"
#include "../operator_location.hpp"

namespace FLINK {


struct ResourceManager_t {

    explicit ResourceManager_t(uint32_t n_nodes)
    {
        refResources_.reserve(n_nodes);
    }

    void               registerResource(TaskManager_t&)               noexcept;
    slotId_t           assignResource(operId_t const, nodeId_t)       noexcept;
    TaskSlot_t const&  slotFrom(OperatorLocation_t const&)      const noexcept;
    TaskSlot_t&        slotFrom(OperatorLocation_t const&)            noexcept;

private:
    std::vector<TaskManager_t*> refResources_{};
};

} // namespace FLINK