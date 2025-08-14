/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Jobmanager definition
*/
#pragma once
#include "../cluster_config.hpp"
#include "resourcemanager.hpp"
#include "jobmaster.hpp"
//#include "../../atomics/node.hpp"

// Cadmium
//#include <cadmium/modeling/dynamic_model.hpp>
//#include <cadmium/modeling/dynamic_model_translator.hpp>
//using namespace cadmium;
//using namespace std;

namespace FLINK {


struct JobManager_t {

    explicit JobManager_t(ClusterConfig_t const& c_cgf)
    : cluster_cfg_{c_cgf} , jobMaster_{cluster_cfg_.topology_}, resourceMan_{}
    {
        std::srand(std::time(nullptr)); // Set seed.
    }

// Methods
    template<typename Callable>
    void deployJob(Callable&& createNodes) noexcept;
    /*{
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
    }*/

    //void deployJob(std::vector<shared_ptr<dynamic::modeling::model>>&)                                noexcept;
    [[nodiscard]] OperatorLocation_t                  getOperLocationLessload(operId_t const&)  const noexcept;
    [[nodiscard]] std::vector<operId_t const*> const& getOperatorDestinations(operId_t const&)  const noexcept;
    [[nodiscard]] double getTimeExecution(operId_t const&)                                      const noexcept;

    //ClusterConfig_t const& getClusterCfg() const noexcept { return cluster_cfg_; }
    [[nodiscard]] operId_t const& firstOperator()                const noexcept;
    [[nodiscard]] bool            lastOperator(operId_t const&)  const noexcept;

private:
    ClusterConfig_t const& cluster_cfg_;

// Two principal components
    JobMaster_t         jobMaster_;
    ResourceManager_t   resourceMan_;
};

} // namespace FLINK