//#include "jobmanager.hpp"
#include "../../atomics/node_master.hpp"


namespace FLINK {

template<typename Callable>
void JobManager_t::deployJob(Callable&& createNodes) noexcept
{
    uint32_t nNodes { cluster_cfg_.n_nodes_ };
    uint32_t nCores { cluster_cfg_.n_cores_ };
    std::vector<Node_t<TIME>*> nodes;

    createNodes(nNodes, nCores, nodes);

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

}
