/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Jobmaster implementation
*/
#include "jobmaster.hpp"

namespace FLINK {

void JobMaster_t::addLocation(operId_t const& oper_id, nodeId_t node_id, slotId_t slot_id) noexcept
{
    auto loc_iter = operLocations_.find(oper_id);
    if (loc_iter != end(operLocations_)){
        loc_iter->second.emplace_back(node_id, slot_id);
    }
    else operLocations_[oper_id].emplace_back(node_id, slot_id);
}

[[nodiscard]] std::vector<OperatorLocation_t> const& 
JobMaster_t::locations(operId_t const& oper_id) const noexcept
{
    auto loc_iter = operLocations_.find(oper_id);
    return loc_iter->second;
}

[[nodiscard]] std::vector<operId_t> const& 
JobMaster_t::operDestinations(operId_t const& oper_id) const noexcept
{
    auto dest_iter = logicGraph_.find(oper_id);
    return dest_iter->second;
}

} // namespace FLINK 