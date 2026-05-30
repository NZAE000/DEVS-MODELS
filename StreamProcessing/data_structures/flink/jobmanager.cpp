#include "jobmanager.hpp"
//#include "../../atomics/node_master.hpp"
//#include<iostream>

namespace FLINK {


// Load balancing: find less congested location.
OperatorLocation_t 
JobManager_t::getOperLocationLessload(operId_t const& oper_id) const noexcept
{
    std::vector<OperatorLocation_t> const& 
    locations = jobMaster_.getLocations(oper_id); // Get all operator's locations ( (node_id, slot_id)...).
    
    OperatorLocation_t const* loc_less_congested {nullptr};
    std::vector<OperatorLocation_t const*> free_locs{};
    std::vector<OperatorLocation_t const*> locs_shorter_queue{};
    free_locs.reserve(locations.size());
    locs_shorter_queue.reserve(locations.size());

    uint32_t shorter_queue { std::numeric_limits<uint32_t>::max() }, n_tuple{};

    // Detect free slots or shorter tuples queue.
    for (auto const& loc : locations)
    {
        auto const& slot = resourceMan_.slotFrom(loc);
        if (!slot.isActive()) free_locs.push_back(&loc); // Detect free slot.
        else 
        {
            n_tuple = slot.nTuples();    // Know n tuples from slot´s queue of node.
            if (n_tuple < shorter_queue)
                shorter_queue = n_tuple;
        }
    }

    // Are there free slots? Choose random.
    auto num_loc_fre = free_locs.size();
    if (num_loc_fre > 0){
        loc_less_congested = free_locs.at(std::rand() % num_loc_fre);
        //std::cout<<"num_loc_fre: "<<num_loc_fre<<"\n";
        //std::cout<<"num_loc_fre: "<<num_loc_fre<<" Chosen node id: "<<loc_less_congested->node_id<<"\n";
    }
    else 
    {   // Store locations with shorter tuple queue.
        for (auto const& loc : locations)
        {
            n_tuple = resourceMan_.slotFrom(loc).nTuples(); // Know n tuples from slot´s queue of node.
            if (n_tuple == shorter_queue)
                locs_shorter_queue.push_back(&loc); // Slot with shorter queque detected.
        }
        loc_less_congested = locs_shorter_queue.at(std::rand() % locs_shorter_queue.size()); // Choose random.
    }

    //std::cout<<"locs of "<<oper_id<<": \n";
    //for (auto const& loc : locations){
    //    std::cout<<"\t"<<loc.node_id<<" "<<loc.slot_id<<"\n";
    //}
    return *loc_less_congested;
}

std::vector<operId_t const*> const&
JobManager_t::getOperatorDestinations(operId_t const& oper_id) const noexcept
{
    auto topo_iter = cluster_cfg_.topology_.find(&oper_id);
    return topo_iter->second;
}

double 
JobManager_t::getTimeExecution(operId_t const& oper_id) const noexcept
{   
    auto oper_props_iter = cluster_cfg_.operProps_.find(oper_id);
    //double t_base { oper_props_iter->second.random_->generate() };
    
    // Apply model degradation
    //double t_eff  { t_base * cluster_cfg_.interferency_ * cluster_cfg_.saturation_ * cluster_cfg_.p_inefficiency_ };
    //return t_eff;
    return oper_props_iter->second.random_time_->generate();
    //return oper_props_iter->second.distribution();
}

double 
JobManager_t::getDegradationFactor() const noexcept {
    return this->cluster_cfg_.degradation_factor_;
}

void JobManager_t::
accumBusyTime(operId_t const& operid, double time) noexcept
{
    this->cluster_cfg_.accumBusyTime(operid, time);
}

void JobManager_t::
accumSentRecords(operId_t const& operid, uint32_t n_rec) noexcept
{
    this->cluster_cfg_.accumSentRecords(operid, n_rec);
}


[[nodiscard]] 
operId_t const& JobManager_t::
getFirstOperator() const noexcept { return *cluster_cfg_.begin_op; }


[[nodiscard]] bool JobManager_t::
lastOperator(operId_t const& oper_id) const noexcept 
{ 
    bool last {false};
    for (auto const* end_op : cluster_cfg_.end_ops){
        if (oper_id == *end_op){ // Match with some last operator? Confirm.
            last = true;
            break;
        }
    }
    return last;   
}

[[nodiscard]] OperatorProperties_t const&  JobManager_t::
getOperatorProperties(operId_t const& operid) const noexcept
{
    auto prop_it = this->cluster_cfg_.operProps_.find(operid);
    return prop_it->second;
}

[[nodiscard]] OperatorProperties_t&  JobManager_t::
getOperatorProperties(operId_t const& operid) noexcept
{
    auto prop_it = const_cast<ClusterConfig_t&>(this->cluster_cfg_).operProps_.find(operid);
    return prop_it->second;
}


} // namespace FLINK