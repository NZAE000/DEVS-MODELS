/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskmanager definition
*/
#pragma once
#include <string>
#include <unordered_map>
#include "executionbuffer.hpp"
#include "taskslot.hpp"
#include "../operatorlocation.hpp"


namespace streamprcss {
    namespace flink {

    struct JobManager_t; // Forward declaration

    struct TaskManager_t {

        explicit TaskManager_t(uint32_t n_cores) 
        : n_cores_{n_cores} 
        {
            //std::cout<<"NCORES: "<<n_cores<<"\n";
            exec_buffers_.reserve(n_cores);
            for (coreId_t i=0; i < n_cores; ++i) 
                exec_buffers_.emplace_back(SUBTASKS_CAPACITY_);
    
            active_subtasks_.reserve(n_cores);
            slots_used_.reserve(n_cores);
        }

    // Methods
        [[nodiscard]] slotId_t                  reserveSlot(operId_t)                           noexcept;
        TaskSlot_t const&                       getSlot(slotId_t)                         const noexcept;
        TaskSlot_t&                             getSlot(slotId_t)                               noexcept;
        std::unordered_map
        <slotId_t, TaskSlot_t> const&           getSlots()                                const noexcept;
        void                                    scheduleExec(mssgId_t, slotId_t, JobManager_t&) noexcept; 
        void                                    checkQueuedExecution(slotId_t, JobManager_t&)   noexcept;
        std::vector<ActiveSubtask_t*>&          getActiveExecutions()                           noexcept;
        std::vector<slotId_t> const&            terminateActiveExecutions()                     noexcept;
        std::size_t                             pendingExecutions()                       const noexcept;
        std::size_t                             executing()                               const noexcept;
        std::vector<ExecutionBuffer_t> const&   getExecutionBuffers()                     const noexcept 
        { return exec_buffers_; }

    private:
        void createSubTask(JobManager_t&, TaskSlot_t&, mssgId_t, slotId_t) noexcept;

        std::vector<ExecutionBuffer_t>            exec_buffers_      {};           // Cores here!.
        std::unordered_map<slotId_t, TaskSlot_t>  taskslots_         {};           // Slots here!. 
        std::vector<ActiveSubtask_t*>             active_subtasks_   {};
        std::vector<slotId_t>                     slots_used_        {};
        coreId_t                                  n_cores_           { 1 };
        slotId_t                                  next_slot_id_      { 0 };
        std::size_t                               pending_execs_     { 0 };
        inline static constexpr std::size_t       SUBTASKS_CAPACITY_ { 100000 };
    };

    } // namespace flink
} // namespace streamprcss