#include "jobmanager.hpp"
#include "../../atomics/node_master.hpp"
//#include<iostream>

namespace FLINK {

void JobManager_t::deployJob(std::vector<shared_ptr<dynamic::modeling::model>>& abstract_nodes) noexcept
{
    uint32_t nNodes { cluster_cfg_.n_nodes_ };
    std::vector<Node_t<TIME>*> nodes;
    abstract_nodes.reserve(nNodes);
    nodes.reserve(nNodes); 

    // Create always first node (master=node_0).
    abstract_nodes.emplace_back(dynamic::translate::make_dynamic_atomic_model<NodeMaster_t, TIME, JobManager_t&>("node_0", *this));
    nodes.push_back(dynamic_cast<Node_t<TIME>*>(abstract_nodes.begin()->get()));

    // Create slave nodes (node_1, node_2, ..., node_n).
    std::string name_base{"node_"}, fullname{};
    for (uint32_t id=1; id<nNodes; ++id)
    {
        fullname = name_base + std::to_string(id);
        abstract_nodes.emplace_back(dynamic::translate::make_dynamic_atomic_model<Node_t, TIME, JobManager_t&>(fullname, *this));
        nodes.push_back(dynamic_cast<Node_t<TIME>*>((abstract_nodes.begin() + id)->get())); // Next interation, get down to subclase (atomic_model -> node) and store address.
    }

    // Agregate all references to taskmanagers.
    std::for_each(nodes.begin(), nodes.end(), [&](auto& node_){
        resourceMan_.agregateResource(node_->id(), node_->getTaskManager());
    });

    uint32_t replica{};
    slotId_t slot_id{};
    auto node_iter     = nodes.begin();
    Node_t<TIME>* node = *node_iter.base();

    // Assign resource to all operators.
    for (auto const& [oper_id, properties] : cluster_cfg_.operProps_)
    {   
        replica = properties.replication; // Operator parallelism (suboperators).
        for (auto i=0; i<replica; i++)
        {
            slot_id = resourceMan_.assignResource(oper_id, node->id());             // Assign resource to operator.
            jobMaster_.addLocation(oper_id, node->id(), slot_id);                   // Store location (node_id, slot_id) of this suboperator.
            if (++node_iter == end(nodes)) node_iter = nodes.begin();               // Next node (if is end, then go back to begin node).
            node = *node_iter.base();
        }
    }

    // Show distribution.
    for (auto const& [oper_id, properties] : cluster_cfg_.operProps_)
    {
        auto locations = jobMaster_.getLocations(oper_id);
        std::cout<<"Locations of "<<oper_id<<":\n";
        for (auto const& loc : locations){
            std::cout<<"\tnode: "<<loc.node_id<<" slot_id: "<<loc.slot_id<<"\n";
        }
    }
}

// Load balancing: find less congested location.
OperatorLocation_t const& 
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

double JobManager_t::getTimeExecution(operId_t const& oper_id) const noexcept
{   
    auto oper_props_iter = cluster_cfg_.operProps_.find(oper_id);
    return oper_props_iter->second.distribution();
}


[[nodiscard]] 
operId_t const& JobManager_t::
firstOperator() const noexcept { return *cluster_cfg_.begin_op; }


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


} // namespace FLINK