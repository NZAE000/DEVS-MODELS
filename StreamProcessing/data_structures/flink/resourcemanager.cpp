/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskslot imlementation
*/
#include "resourcemanager.hpp"

namespace FLINK {

slotId_t ResourceManager_t::assignResource(operId_t const& oper_id, TaskManager_t& taskMan) const noexcept
{
    slotId_t slot_id = taskMan.reserveSlot(oper_id);
    return slot_id;
}

void ResourceManager_t::addRefResource(nodeId_t node_id, TaskManager_t& taskMan) noexcept
{
    refResources_[node_id] = &taskMan;
}

uint32_t ResourceManager_t::nTupleQueue(OperatorLocation_t const& operatorLocation) const noexcept
{
    auto const [node_id, slot_id] = operatorLocation;
    auto iter = refResources_.find(node_id);

    return iter->second->getNTuples(slot_id);
}

} // namespace FLINK