/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* ResourceManager imlementation
*/
#include "resourcemanager.hpp"

namespace streamprcss {
    namespace flink {

    void ResourceManager_t::registerResource(TaskManager_t& taskman) noexcept
    {
        ref_resources_.emplace_back(&taskman);
    }

    slotId_t ResourceManager_t::assignResource(operId_t oper_id, nodeId_t node_id) noexcept
    {
        slotId_t slot_id = ref_resources_[node_id]->reserveSlot(oper_id);
        return slot_id;
    }

    TaskSlot_t const& ResourceManager_t::slotFrom(OperatorLocation_t const& operatorLocation) const noexcept
    {
        auto const [_, node_id, slot_id] = operatorLocation;
        return ref_resources_[node_id]->getSlot(slot_id);
    }

    TaskSlot_t& ResourceManager_t::slotFrom(OperatorLocation_t const& operatorLocation) noexcept
    {
        auto& slot = const_cast<ResourceManager_t const*>(this)->slotFrom(operatorLocation);
        return *const_cast<TaskSlot_t*>(&slot);
    }

    } // namespace flink
} // namespace streamprcss