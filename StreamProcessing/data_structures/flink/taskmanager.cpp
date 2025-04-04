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

uint32_t 
TaskManager_t::getNTuples(slotId_t slot_id) const noexcept
{
    auto const taskSlot_iter = taskSlots_.find(slot_id);
    return taskSlot_iter->second.nTuples();
}

operId_t const& 
TaskManager_t::getOperator(slotId_t slot_id) const noexcept
{
    auto taskSlot_iter = taskSlots_.find(slot_id);
    return taskSlot_iter->second.getOperator();
}

void 
TaskManager_t::scheduleExec(slotId_t slot_id, JobManager_t& jobMan) noexcept
{
    TaskSlot_t& slot = taskSlots_[slot_id]; // Get task slot

    if (slot.isRunnig()) slot.pushTuple(); // Queuing on buffer
    else 
    {
        int lapse { static_cast<int>(std::round(jobMan.getAvgExecution(slot.getOperator()))) }; // Get avg time excecution with some distribution
        createExecution(slot, slot_id, lapse);
    }
}

void 
TaskManager_t::checkNextExecution(slotId_t slot_id, JobManager_t& jobMan) noexcept
{
    TaskSlot_t& slot = taskSlots_[slot_id]; // Get task slot

    if (slot.pendingTuples()) // Has pending tuples to execute? 
    {
        slot.popTuple();  // Remove tuple from slot buffer
        int lapse { static_cast<int>(std::round(jobMan.getAvgExecution(slot.getOperator()))) };  // Get avg time excecution with some distribution
        createExecution(slot, slot_id, lapse);

    } else slot.setExecution(false);
}

void 
TaskManager_t::createExecution(TaskSlot_t slot, slotId_t slot_id, int lapse) noexcept 
{
    TIME timeExec = {0,0,0,0,lapse};                        // Create time execution
    this->bufferExec_.emplace_back(slot_id, timeExec);      // Add to execution buffer
    slot.setExecution(true);                                // State to execute 
}

Subtask_t& 
TaskManager_t::getPriorityExecution() noexcept {
    auto const* exec_pending { &const_cast<TaskManager_t const*>(this)->getPriorityExecution() };
    return const_cast<Subtask_t&>(*exec_pending);
}

Subtask_t const& 
TaskManager_t::getPriorityExecution() const noexcept
{
    return *bufferExec_.begin();
}

slotId_t
TaskManager_t::dropPriorityExecution() noexcept
{
    slotId_t slot_id { getPriorityExecution().slot_id };
    bufferExec_.erase(bufferExec_.begin());

    return slot_id;
}

bool  
TaskManager_t::executionPending() const noexcept
{
    return bufferExec_.size();
}

} // namespace FLINK