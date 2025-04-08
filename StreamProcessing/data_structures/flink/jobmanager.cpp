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

    // Create always first node (master).
    abstract_nodes.emplace_back(dynamic::translate::make_dynamic_atomic_model<NodeMaster_t, TIME, JobManager_t&>("node_0", *this));
    nodes.push_back(dynamic_cast<Node_t<TIME>*>(abstract_nodes.begin()->get()));

    // Create slave nodes.
    std::string name_base{"node_"}, fullname{};
    for (uint32_t id=1; id<nNodes; ++id)
    {
        fullname = name_base + std::to_string(id);
        abstract_nodes.emplace_back(dynamic::translate::make_dynamic_atomic_model<Node_t, TIME, JobManager_t&>(fullname, *this));
        nodes.push_back(dynamic_cast<Node_t<TIME>*>((abstract_nodes.begin() + id)->get())); // Next interation, get down to subclase (atomic_model -> node) and store address.
    }

    uint32_t replica{};
    slotId_t slot_id{};
    auto node_iter     = nodes.begin();
    Node_t<TIME>* node = *node_iter.base();

    // Assign resource to all operators.
    for (auto const& [oper_id, properties] : cluster_cfg_.operProps_)
    {   
        replica = properties.replication; // Operator parallelism (suboperators)
        for (auto i=0; i<replica; i++)
        {
            slot_id = resourceMan_.assignResource(oper_id, node->getTaskManager()); // Assign resource to operator
            jobMaster_.addLocation(oper_id, node->id(), slot_id);  // Store location (node_id, slot_id) of this suboperator.
            if (++node_iter == end(nodes)) node_iter = nodes.begin();   // Next node (if is end, then go back to begin node)
            node = *node_iter.base();
        }
    }

    // Store all references to taskmanagers
    std::for_each(nodes.begin(), nodes.end(), [&](auto& node_){
        resourceMan_.addRefResource(node_->id(), node_->getTaskManager());
    });

    // Show distribution.
    for (auto const& [oper_id, properties] : cluster_cfg_.operProps_)
    {
        auto locations = jobMaster_.locations(oper_id);
        std::cout<<"locaciones de "<<oper_id<<":\n";
        for (auto const& loc : locations){
            std::cout<<"\tnode: "<<loc.node_id<<" slot_id: "<<loc.slot_id<<"\n";
        }
    }
}

OperatorLocation_t const& 
JobManager_t::getOperLocationLessload(operId_t const& oper_id) const noexcept
{
    std::vector<OperatorLocation_t> const& 
    locations = jobMaster_.locations(oper_id); // Get all operator's locations ( (node_id, slot_id)...).

    // Find less congested location.
    uint32_t less { std::numeric_limits<uint32_t>::max() }, nTuple{};
    OperatorLocation_t const* loc_less_congested {nullptr};
    for (auto const& loc : locations)
    {
        nTuple = resourceMan_.slotFrom(loc).nTuples(); // Know n tuples from slot´s queue of node.
        if (nTuple < less) {
            less = nTuple;
            loc_less_congested = &loc;
        }
    }

    //std::cout<<"locs of "<<oper_id<<": \n";
    //for (auto const& loc : locations){
    //    std::cout<<"\t"<<loc.node_id<<" "<<loc.slot_id<<"\n";
    //}
    return *loc_less_congested;
}

std::vector<operId_t> const&
JobManager_t::getOperatorDestinations(operId_t const& oper_id) const noexcept
{
    auto topo_iter = cluster_cfg_.topology_.find(oper_id);
    return topo_iter->second;
}

double JobManager_t::getAvgExecution(operId_t const& oper_id) const noexcept
{   
    auto oper_props_iter = cluster_cfg_.operProps_.find(oper_id);
    return oper_props_iter->second.distribution();
}

} // namespace FLINK