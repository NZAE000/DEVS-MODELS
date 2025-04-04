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

// Methods
slotId_t assignResource(operId_t const&, TaskManager_t&) const noexcept;
void addRefResource(nodeId_t, TaskManager_t&)                  noexcept;
uint32_t nTupleQueue(OperatorLocation_t const&)          const noexcept;

private:
    std::map<nodeId_t, TaskManager_t*> refResources_;
};

} // namespace FLINK