/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskslot definition
*/
#pragma once
#include "taskmanager.hpp"
#include "../operator_location.hpp"

namespace FLINK {


struct ResourceManager_t {

    void agregateResource(nodeId_t, TaskManager_t&)                noexcept;
    slotId_t assignResource(operId_t const&, nodeId_t)             noexcept;
    TaskSlot_t const& slotFrom(OperatorLocation_t const&)    const noexcept;
    TaskSlot_t& slotFrom(OperatorLocation_t const&)                noexcept;

private:
    std::map<nodeId_t, TaskManager_t*> refResources_;
};

} // namespace FLINK