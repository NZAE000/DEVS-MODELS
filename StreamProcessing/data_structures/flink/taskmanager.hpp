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
#include "taskslot.hpp"
#include "../operator_location.hpp"

//Time class header
#include <NDTime.hpp>
using TIME = NDTime;

namespace FLINK {

struct Subtask_t {

    Subtask_t(mssgId_t mssgid, slotId_t sid, TIME const& time)
    : mssg_id{mssgid}, slot_id{sid}, lapse_{time} {}

    mssgId_t mssg_id;
    slotId_t slot_id;
    TIME     lapse_;
};


struct JobManager_t; // Forward declaration

struct TaskManager_t {

    explicit TaskManager_t(uint32_t n_cores) 
    : n_cores_{n_cores} 
    {
        //std::cout<<"NCORES: "<<n_cores<<"\n";
        for (coreId_t i=0; i<n_cores; ++i) 
            exec_buffers[i].reserve(1000);

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
    { return exec_buffers; }

private:
    void createSubTask(JobManager_t&, TaskSlot_t&, mssgId_t, slotId_t) noexcept;

    std::map<coreId_t, std::vector<Subtask_t>>  exec_buffers;           // Cores here!.
    std::map<slotId_t, TaskSlot_t>              taskslots_;            // Slots here!. 
    mutable std::vector<Subtask_t*>             priority_execs_;
            std::vector<slotId_t>               slots_used_;
    coreId_t                                    n_cores_{1};
    slotId_t                                    next_slot_id_ {0};
    mutable std::size_t                         current_execs_{0};
};

} // namespace FLINK