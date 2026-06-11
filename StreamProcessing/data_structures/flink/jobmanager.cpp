#include "jobmanager.hpp"
//#include "../../atomics/node_master.hpp"
//#include<iostream>

namespace FLINK {


// Load balancing: find less congested location.
OperatorLocation_t 
JobManager_t::getOperLocationLessload(operId_t const oper_id) const noexcept
{
    std::vector<OperatorLocation_t> const& 
    locations = this->jobMaster_.getLocations(oper_id); // Get all operator's locations ( (mssg_id, node_id, slot_id)...).
    
    OperatorLocation_t const* loc_less_congested  { nullptr };
    uint32_t shorter_queue                        { std::numeric_limits<uint32_t>::max() };
    uint32_t n_tuple                              {};

    // Detect free slots or shorter tuples queue.
    for (auto const& loc : locations)
    {
        auto const& slot = this->resourceMan_.slotFrom(loc);
        if (!slot.isActive()) this->free_locs_.emplace_back(&loc); // Detect free slot.
        else 
        {
            n_tuple = slot.nTuples();    // Know n tuples from slot´s queue of node.
            if (n_tuple < shorter_queue)
                shorter_queue = n_tuple;
        }
    }

    // Are there free slots? Choose random.
    auto num_loc_fre = this->free_locs_.size();
    if (num_loc_fre > 0){
        loc_less_congested = this->free_locs_.at(std::rand() % num_loc_fre);
        //std::cout<<"num_loc_fre: "<<num_loc_fre<<"\n";
        //std::cout<<"num_loc_fre: "<<num_loc_fre<<" Chosen node id: "<<loc_less_congested->node_id<<"\n";
    }
    else 
    {   // Store locations with shorter tuple queue.
        for (auto const& loc : locations)
        {
            n_tuple = this->resourceMan_.slotFrom(loc).nTuples(); // Know n tuples from slot´s queue of node.
            if (n_tuple == shorter_queue)
                this->locs_shorter_queue_.emplace_back(&loc); // Slot with shorter queque detected.
        }
        loc_less_congested = this->locs_shorter_queue_.at(std::rand() % this->locs_shorter_queue_.size()); // Choose random.
    }

    //std::cout<<"locs of "<<oper_id<<": \n";
    //for (auto const& loc : locations){
    //    std::cout<<"\t"<<loc.node_id<<" "<<loc.slot_id<<"\n";
    //}
    this->free_locs_.clear();
    this->locs_shorter_queue_.clear();
    
    return *loc_less_congested;
}

std::vector<operId_t> const&
JobManager_t::getOperatorDestinations(operId_t const oper_id) const noexcept
{
    auto const& dest = cluster_cfg_.topology_[oper_id];
    return dest;
}

double 
JobManager_t::getTimeExecution(operId_t const oper_id) const noexcept
{   
    auto const& oper_prop = cluster_cfg_.operProps_[oper_id];
    return oper_prop.random_time_->generate();
}

double 
JobManager_t::getDegradationFactor() const noexcept {
    return this->cluster_cfg_.degradation_factor_;
}

void JobManager_t::
accumBusyTime(operId_t const operid, double time) noexcept
{
    this->cluster_cfg_.accumBusyTime(operid, time);
}

void JobManager_t::
accumSentRecords(operId_t const operid, uint32_t n_rec) noexcept
{
    this->cluster_cfg_.accumSentRecords(operid, n_rec);
}


[[nodiscard]] 
operId_t JobManager_t::
getFirstOperator() const noexcept { return cluster_cfg_.begin_op_; }


[[nodiscard]] bool JobManager_t::
lastOperator(operId_t const oper_id) const noexcept 
{ 
    bool last {false};
    for (auto const end_op : cluster_cfg_.end_ops_){
        if (oper_id == end_op){ // Match with some last operator? Confirm.
            last = true;
            break;
        }
    }
    return last;   
}

[[nodiscard]] OperatorProperties_t const&  JobManager_t::
getOperatorProperties(operId_t const operid) const noexcept
{
    auto const& prop = this->cluster_cfg_.operProps_[operid];
    return prop;
}

[[nodiscard]] OperatorProperties_t&  JobManager_t::
getOperatorProperties(operId_t const operid) noexcept
{
    auto& prop = const_cast<ClusterConfig_t&>(this->cluster_cfg_).operProps_[operid];
    return prop;
}


} // namespace FLINK