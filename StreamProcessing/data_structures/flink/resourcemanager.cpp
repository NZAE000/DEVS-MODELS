/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskslot imlementation
*/
#include "resourcemanager.hpp"

namespace FLINK {

void ResourceManager_t::agregateResource(nodeId_t node_id, TaskManager_t& taskMan) noexcept
{
    refResources_[node_id] = &taskMan;
}

slotId_t ResourceManager_t::assignResource(operId_t const& oper_id, nodeId_t node_id) noexcept
{
    slotId_t slot_id = refResources_[node_id]->reserveSlot(oper_id);
    return slot_id;
}

TaskSlot_t const& ResourceManager_t::slotFrom(OperatorLocation_t const& operatorLocation) const noexcept
{
    auto const [_, node_id, slot_id] = operatorLocation;
    auto iter = refResources_.find(node_id);

    return iter->second->getSlot(slot_id);
}

TaskSlot_t& ResourceManager_t::slotFrom(OperatorLocation_t const& operatorLocation) noexcept
{
    auto& slot = const_cast<ResourceManager_t const*>(this)->slotFrom(operatorLocation);
    return *const_cast<TaskSlot_t*>(&slot);
}

} // namespace FLINK