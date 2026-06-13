//#include "jobmanager.hpp"
#include <atomics/nodemaster.hpp>
#include <iostream>


namespace streamprcss {
    namespace flink {

    template<typename Callable>
    void JobManager_t::deployJob(Callable&& createNodes) noexcept
    {
        uint32_t nNodes { cluster_cfg_.n_nodes_ };
        uint32_t nCores { cluster_cfg_.n_cores_ };
        std::vector<streamprcss::Node_t<TIME>*> nodes;

        createNodes(nNodes, nCores, nodes); // InItialize nodes.

        // Resourcemanager registry taskmanagers: agregate all taskmanagers references.
        std::for_each(nodes.begin(), nodes.end(), [&](auto& node_){
            resourceMan_.registerResource(node_->getTaskManager());
        });

        std::vector<streamprcss::Node_t<TIME>*>::iterator node_iter = nodes.begin();
        streamprcss::Node_t<TIME>*                        node      = *node_iter.base();
        uint32_t  replica  {};
        slotId_t  slot_id  {};

        // Assign resource to all operators.
        uint32_t n_oper { cluster_cfg_.N_OPERATORS_ };
        for (operId_t oper_id=0; oper_id < n_oper; ++oper_id)
        {   
            auto const& properties = cluster_cfg_.operProps_[oper_id];
            replica = properties.replication_; // Operator parallelism (suboperators).
            for (uint32_t i=0; i < replica; i++)
            {
                slot_id = resourceMan_.assignResource(oper_id, node->id());   // Assign resource to operator.
                jobMaster_.addLocation(oper_id, node->id(), slot_id);         // Store location (node_id, slot_id) of this suboperator.
                if (++node_iter == end(nodes)) node_iter = nodes.begin();     // Next node (if is end, then go back to begin node).
                
                node = *node_iter.base();
            }
        }

        //// Show distribution.
        //for (auto const& [oper_id, properties] : cluster_cfg_.operProps_)
        //{
        //    auto locations = jobMaster_.getLocations(oper_id);
        //    std::cout<<"Locations of "<<oper_id<<":\n";
        //    for (auto const& loc : locations){
        //        std::cout<<"\tnode: "<<loc.node_id<<" slot_id: "<<loc.slot_id<<"\n";
        //    }
        //}
    }

    } // namespace flink
} // namespace streamprcss
