/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskmanager implementation
*/
#include "taskmanager.hpp"
#include "jobmanager.hpp"
#include<algorithm>

namespace FLINK {

[[nodiscard]] slotId_t 
TaskManager_t::reserveSlot(operId_t const& oper_id) noexcept
{
    auto pair = taskSlots_.insert(std::pair<slotId_t, operId_t>(nextID++, oper_id));
    return pair.first->first;
}

TaskSlot_t const& 
TaskManager_t::getSlot(slotId_t id) const noexcept
{
    auto taskSlot_iter = taskSlots_.find(id);
    return taskSlot_iter->second;
}
TaskSlot_t&       
TaskManager_t::getSlot(slotId_t id) noexcept
{
    auto& slot = const_cast<TaskManager_t const*>(this)->getSlot(id);
    return *const_cast<TaskSlot_t*>(&slot);
}

std::map<slotId_t, TaskSlot_t> const&
TaskManager_t::getSlots() const noexcept
{
    return taskSlots_;
}

void 
TaskManager_t::scheduleExec(slotId_t slot_id, JobManager_t& jobMan) noexcept
{
    TaskSlot_t& slot = taskSlots_[slot_id]; // Get task slot.

    if (slot.isRunnig()) slot.pushTuple(); // Queuing on buffer.
    else 
    {
        // Get avg time excecution with some distribution and create execution.
        int lapse { static_cast<int>(std::round(jobMan.getAvgExecution(slot.getOperator()))) };
        createSubTask(slot, slot_id, lapse);
    }
}

void 
TaskManager_t::checkQueuedExecution(slotId_t slot_id, JobManager_t& jobMan) noexcept
{
    TaskSlot_t& slot = taskSlots_[slot_id]; // Get task slot.

    if (slot.pendingTuples()) // Has pending tuples to execute? 
    {
        slot.popTuple();  // Remove tuple from slot buffer.
        // Get avg time excecution with some distribution and create execution.
        int lapse { static_cast<int>(std::round(jobMan.getAvgExecution(slot.getOperator()))) };
        createSubTask(slot, slot_id, lapse);

    } else slot.setExecution(false);
}

void 
TaskManager_t::createSubTask(TaskSlot_t& slot, slotId_t slot_id, int lapse) noexcept 
{
    TIME timeExec = {0,0,0,0,/*lapse*/10};                        // Create time execution.
    this->bufferExec_.emplace_back(slot_id, timeExec);      // Add to execution buffer.
    slot.setExecution(true);                                // State to execute.
}

Subtask_t const& 
TaskManager_t::getPriorityExecution() const noexcept
{
    return *bufferExec_.begin();
}

Subtask_t& 
TaskManager_t::getPriorityExecution() noexcept {
    auto const* exec_pending { &const_cast<TaskManager_t const*>(this)->getPriorityExecution() };
    return const_cast<Subtask_t&>(*exec_pending);
}

slotId_t
TaskManager_t::terminatePriorityExecution() noexcept
{
    // Get the slot_id used and delete what was executed.
    slotId_t slot_id_used { getPriorityExecution().slot_id };
    bufferExec_.erase(bufferExec_.begin());

    return slot_id_used;
}

std::size_t  
TaskManager_t::executionPending() const noexcept
{
    return bufferExec_.size();
}

} // namespace FLINK