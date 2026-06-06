/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskmanager definition
*/
#pragma once
#include<iostream>
#include<string>
#include<map>
#include "executionbuffer.hpp"
#include "taskslot.hpp"
#include "../operator_location.hpp"


namespace FLINK {


struct JobManager_t; // Forward declaration

struct TaskManager_t {

    explicit TaskManager_t(uint32_t n_cores) 
    : n_cores_{n_cores} 
    {
        //std::cout<<"NCORES: "<<n_cores<<"\n";
        for (coreId_t i=0; i < n_cores; ++i) 
            exec_buffers_.insert({i, ExecutionBuffer_t(SUBTASKS_CAPACITY)});
 
        priority_execs_.reserve(n_cores);
        slots_used_.reserve(n_cores);
    }

// Methods
    [[nodiscard]] slotId_t                  reserveSlot(operId_t const&)                    noexcept;
    TaskSlot_t const&                       getSlot(slotId_t)                         const noexcept;
    TaskSlot_t&                             getSlot(slotId_t)                               noexcept;
    std::map<slotId_t, TaskSlot_t> const&   getSlots()                                const noexcept;
    void                                    scheduleExec(mssgId_t, slotId_t, JobManager_t&) noexcept; 
    void                                    checkQueuedExecution(slotId_t, JobManager_t&)   noexcept;
    std::vector<Subtask_t*>&                getPriorityExecutions()                         noexcept;
    std::vector<slotId_t> const&            terminatePriorityExecutions()                   noexcept;
    std::size_t                             pendingExecutions()                       const noexcept;
    std::size_t                             executing()                               const noexcept;
    auto const&                             getExecBuffers()                          const noexcept 
    { return exec_buffers_; }

private:
    void createSubTask(JobManager_t&, TaskSlot_t&, mssgId_t, slotId_t) noexcept;

    std::map<coreId_t, ExecutionBuffer_t>  exec_buffers_;           // Cores here!.
    std::map<slotId_t, TaskSlot_t>         taskslots_;             // Slots here!. 
    mutable std::vector<Subtask_t*>        priority_execs_;
            std::vector<slotId_t>          slots_used_;
    coreId_t                               n_cores_{1};
    slotId_t                               next_slot_id_ {0};
    mutable std::size_t                    current_execs_{0};

    inline static constexpr std::size_t    SUBTASKS_CAPACITY {10000000};
};

} // namespace FLINK