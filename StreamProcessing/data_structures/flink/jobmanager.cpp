#include "jobmanager.hpp"
#include "../../atomics/node_master.hpp"
//#include<iostream>

namespace FLINK {

void JobManager_t::deployJob(std::vector<shared_ptr<dynamic::modeling::model>>& nodes) noexcept
{
    uint32_t nNodes { cluster_cfg_.n_nodes_ };
    nodes.reserve(nNodes);

    // Create always first node (master)
    nodes.emplace_back(dynamic::translate::make_dynamic_atomic_model<NodeMaster_t, TIME, JobManager_t&>("node_master", *this));

    // Create slave nodes
    std::string name_base{"node"}, fullname{};
    uint32_t id{};
    for (uint32_t i=1; i<nNodes; ++i){
        fullname = name_base + std::to_string(id);
        nodes.emplace_back(dynamic::translate::make_dynamic_atomic_model<Node_t, TIME, JobManager_t&>(fullname, *this));
        ++id;
    }

    uint32_t replica{};
    slotId_t slot_id{};
    auto node_iter     = nodes.begin();
    Node_t<TIME>* node = dynamic_cast<Node_t<TIME>*>(node_iter->get());

    // Assign resource to all operators
    for (auto& [oper_id, properties] : cluster_cfg_.operProps_)
    {   
        replica = properties.replication; // Operator parallelism (suboperators)
        for (auto i=0; i<replica; i++)
        {
            slot_id = resourceMan_.assignResource(oper_id, node->getTaskManager()); // Assign resource to operator
            jobMaster_.addLocation(oper_id, node->id(), slot_id);  // Store location (node_id, slot_id) of this suboperator.

            if (++node_iter == end(nodes)) node_iter = nodes.begin(); // Next node
            node = dynamic_cast<Node_t<TIME>*>(node_iter->get());
        }
    }

    // Store all references to taskmanagers
    std::for_each(nodes.begin(), nodes.end(), [&](auto& node_){
        node = dynamic_cast<Node_t<TIME>*>(node_.get());
        resourceMan_.addRefResource(node->id(), node->getTaskManager());
    });

    //for (auto& [oper_id, properties] : cluster_cfg_.operProps_)
    //{
    //    auto locations = jobMaster_.locations(oper_id);
    //    std::cout<<"locaciones de "<<oper_id<<":\n";
    //    for (auto const& loc : locations){
    //        std::cout<<"\t node_i: "<<loc.node_id<<" slot_id: "<<loc.slot_id<<"\n";
    //    }
    //}
}

OperatorLocation_t const& 
JobManager_t::getOperLocation_balanced(operId_t const& oper_id) const noexcept
{
    std::vector<OperatorLocation_t> const& 
    locations = jobMaster_.locations(oper_id);

    // Find less congested location 
    uint32_t less { std::numeric_limits<uint32_t>::max() }, nTuple{};
    OperatorLocation_t const* loc_less_congested {nullptr};
    for (auto const loc : locations)
    {
        nTuple = resourceMan_.nTupleQueue(loc); // Know n tuples from slot' queue of node
        if (nTuple < less) {
            less = nTuple;
            loc_less_congested = &loc;
        }
    }

    //std::cout<<"locs of "<<oper_id<<": \n";
    //for (auto const& loc : locations){
    //    std::cout<<"\t"<<loc.node_id<<loc.slot_id<<"\n";
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