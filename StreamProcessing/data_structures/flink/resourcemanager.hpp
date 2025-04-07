/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskslot definition
*/
#pragma once
#include <NDTime.hpp>
#include "taskmanager.hpp"
#include "../operator_location.hpp"

namespace FLINK {

using TIME = NDTime;


struct ResourceManager_t {

    slotId_t assignResource(operId_t const&, TaskManager_t&) const noexcept;
    void addRefResource(nodeId_t, TaskManager_t&)                  noexcept;
    TaskSlot_t const& slotFrom(OperatorLocation_t const&)    const noexcept;
    TaskSlot_t& slotFrom(OperatorLocation_t const&)                noexcept;

private:
    std::map<nodeId_t, TaskManager_t*> refResources_;
};

} // namespace FLINK