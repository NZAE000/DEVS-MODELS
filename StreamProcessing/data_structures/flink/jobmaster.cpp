/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Jobmaster implementation
*/
#include "jobmaster.hpp"


namespace streamprcss {
    namespace flink {

    void JobMaster_t::addLocation(operId_t const oper_id, nodeId_t node_id, slotId_t slot_id) noexcept
    {
        mssgId_t mssgid {0};
        std::vector<OperatorLocation_t>& locations = this->oper_locations_[oper_id];
        locations.emplace_back(mssgid, node_id, slot_id);
    }

    [[nodiscard]] std::vector<OperatorLocation_t> const& 
    JobMaster_t::getLocations(operId_t const oper_id) const noexcept
    {
        return this->oper_locations_[oper_id];
    }

    [[nodiscard]] std::vector<operId_t> const& 
    JobMaster_t::operatorDestinations(operId_t const oper_id) const noexcept
    {
        auto const& dest = this->job_graph_[oper_id];
        return dest;
    }

    } // namespace flink
} //namespace streamprcss