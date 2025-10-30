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
            buffersExec_[i].reserve(1000);

        priorityExecs_.reserve(n_cores);
        slots_used_.reserve(n_cores);
    }

// Methods
    [[nodiscard]] slotId_t reserveSlot(operId_t const&)         noexcept;
    TaskSlot_t const& getSlot(slotId_t)                   const noexcept;
    TaskSlot_t&       getSlot(slotId_t)                         noexcept;
    std::map<slotId_t, TaskSlot_t> const& getSlots()      const noexcept;

    void scheduleExec(mssgId_t, slotId_t, JobManager_t&)        noexcept; 
    void checkQueuedExecution(slotId_t, JobManager_t&)          noexcept;


    std::vector<Subtask_t*>&     getPriorityExecutions()        noexcept;
    std::vector<slotId_t> const* terminatePriorityExecutions()  noexcept;
    std::size_t pendingExecutions()                       const noexcept;

    //std::vector<Subtask_t*> const& getPriorityExecutions() const noexcept;

    //Subtask_t&       getPriorityExecution()                     noexcept;
    //Subtask_t const& getPriorityExecution()               const noexcept;
    //slotId_t         terminatePriorityExecution()               noexcept;
    //std::size_t      executionPending()                   const noexcept;

private:
    void createSubTask(TaskSlot_t&, mssgId_t, slotId_t, int lapse) noexcept;

    std::map<slotId_t, TaskSlot_t>  taskSlots_;
    //std::vector<Subtask_t>          bufferExec_;
    
    std::map<coreId_t, std::vector<Subtask_t>> buffersExec_; // CORES HERE!.
    mutable std::vector<Subtask_t*> priorityExecs_;
            std::vector<slotId_t>   slots_used_;

    coreId_t n_cores_{1};
    slotId_t nextID {0};
};

} // namespace FLINK