/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskslot imlementation
*/
#include "resourcemanager.hpp"

namespace FLINK {

void ResourceManager_t::registerResource(TaskManager_t& taskman) noexcept
{
    refResources_.emplace_back(&taskman);
}

slotId_t ResourceManager_t::assignResource(operId_t const oper_id, nodeId_t node_id) noexcept
{
    slotId_t slot_id = refResources_[node_id]->reserveSlot(oper_id);
    return slot_id;
}

TaskSlot_t const& ResourceManager_t::slotFrom(OperatorLocation_t const& operatorLocation) const noexcept
{
    auto const [_, node_id, slot_id] = operatorLocation;
    return refResources_[node_id]->getSlot(slot_id);
}

TaskSlot_t& ResourceManager_t::slotFrom(OperatorLocation_t const& operatorLocation) noexcept
{
    auto& slot = const_cast<ResourceManager_t const*>(this)->slotFrom(operatorLocation);
    return *const_cast<TaskSlot_t*>(&slot);
}

} // namespace FLINK