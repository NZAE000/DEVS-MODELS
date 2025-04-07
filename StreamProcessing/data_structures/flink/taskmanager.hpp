/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskmanager definition
*/
#pragma once
#include<string>
#include<map>
#include "taskslot.hpp"
#include "../operator_location.hpp"

//Time class header
#include <NDTime.hpp>
using TIME = NDTime;

namespace FLINK {

struct Subtask_t {

    Subtask_t(slotId_t sid, TIME const& time)
    : slot_id{sid}, lapse_{time} {}

    slotId_t slot_id;
    TIME     lapse_;
};


struct JobManager_t; // forwarding declaration

struct TaskManager_t {

    explicit TaskManager_t() = default;

// Methods
    [[nodiscard]] slotId_t reserveSlot(operId_t const&)         noexcept;
    TaskSlot_t const& getSlot(slotId_t)                   const noexcept;
    TaskSlot_t&       getSlot(slotId_t)                         noexcept;
    std::map<slotId_t, TaskSlot_t> const& getSlots()      const noexcept;

    void scheduleExec(slotId_t, JobManager_t&)                  noexcept; 
    void checkQueuedExecution(slotId_t, JobManager_t&)          noexcept;

    Subtask_t&       getPriorityExecution()                     noexcept;
    Subtask_t const& getPriorityExecution()               const noexcept;
    slotId_t         terminatePriorityExecution()               noexcept;
    std::size_t      executionPending()                   const noexcept;

private:
    void createSubTask(TaskSlot_t&, slotId_t, int lapse)      noexcept;

    std::map<slotId_t, TaskSlot_t>  taskSlots_;
    std::vector<Subtask_t>          bufferExec_;

    slotId_t nextID {0};
};

} // namespace FLINK