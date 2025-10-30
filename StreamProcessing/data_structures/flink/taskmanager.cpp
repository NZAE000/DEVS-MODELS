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
    auto pair = taskSlots_.insert(std::pair<slotId_t, operId_t const&>(nextID++, oper_id));
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
TaskManager_t::scheduleExec(mssgId_t mssg_id, slotId_t slot_id, JobManager_t& jobMan) noexcept
{
    TaskSlot_t& slot = getSlot(slot_id); // Get task slot.

    if (slot.isUsing()) slot.pushTuple(mssg_id); // Queuing on buffer.
    else 
    {
        // Get avg time excecution with some distribution and create execution.
        int lapse { static_cast<int>(std::round(jobMan.getTimeExecution(slot.getOperator()))) };
        createSubTask(slot, mssg_id, slot_id, lapse);
    }
}

void 
TaskManager_t::checkQueuedExecution(slotId_t slot_id, JobManager_t& jobMan) noexcept
{
    TaskSlot_t& slot = getSlot(slot_id); // Get task slot.
    if (slot.pendingTuples())            // Has pending tuples to execute? 
    {
        mssgId_t mssg_id = slot.popTuple();  // Remove tuple from slot buffer.
        // Get avg time excecution with some distribution and create execution.
        int lapse { static_cast<int>(std::round(jobMan.getTimeExecution(slot.getOperator()))) };
        createSubTask(slot, mssg_id, slot_id, lapse);

    } //else slot.setExecution(false);
}

void 
TaskManager_t::createSubTask(TaskSlot_t& slot, mssgId_t mssg_id, slotId_t slot_id, int lapse) noexcept 
{
    int lapse_us {lapse};
    int lapse_hr  = lapse_us / 3'600'000'000;
    lapse_us     %= 3'600'000'000;
    int lapse_min = lapse_us / 60'000'000;
    lapse_us     %= 60'000'000;
    int lapse_s   = lapse_us / 1'000'000;
    lapse_us     %= 1'000'000;
    int lapse_ms  = lapse_us / 1'000;
    lapse_us     %= 1'000;

    TIME timeExec = {lapse_hr,lapse_min,lapse_s,lapse_ms,lapse_us}; // hrs::mins:secs:mills:(micrs)::nns:pcs::fms
    //TIME timeExec = {0,0,0,0,lapse};                        // Create time execution (hrs::mins:secs:mills:micrs::nns:pcs::fms).

    // Search core buffer with less congestion.
    std::vector<Subtask_t>* bufferLessCongestion {nullptr};
    uint32_t id_core_select{0};
    std::size_t n_exec_less { std::numeric_limits<uint32_t>::max() };
    for (auto& [id_core, buffer] : buffersExec_){
        auto n_exec {buffer.size()};
        if (n_exec < n_exec_less) {
            n_exec_less = n_exec;
            bufferLessCongestion = &buffer;
            id_core_select = id_core;
        }
    }

    // Add to execution buffer.
    bufferLessCongestion->emplace_back(mssg_id, slot_id, timeExec);
    slot.setUsing(true);
    //std::cout<<slot.getOperator()<<" : "<<slot_id<<" "<<id_core_select<<" "<<bufferLessCongestion->size()<<'\n';
    //if (getPriorityExecution().slot_id == slot_id)
    //    slot.setActive(true);                            // Slot active in execution.
    for (auto& priority_exec : getPriorityExecutions()){
        if (priority_exec->slot_id == slot_id){           // Slot added recently is priority? set active in execution.
            slot.setActive(true);                         
            break;
        }
    }
}

std::vector<Subtask_t*>& 
TaskManager_t::getPriorityExecutions() noexcept
{
    priorityExecs_.clear(); // !
    for (auto& [id_core, buffer] : buffersExec_){
        if (!buffer.empty()){
            priorityExecs_.push_back(buffer.begin().base()); // Collect priority executions.
        }
    }
    return priorityExecs_;
    //return *bufferExec_.begin();
}

//std::vector<Subtask_t*>&
//TaskManager_t::getPriorityExecutions() noexcept {
//    std::vector<Subtask_t*> const& execs_pending { const_cast<TaskManager_t const*>(this)->getPriorityExecutions() };
//    return const_cast<std::vector<Subtask_t*>&>(execs_pending);
//}


std::vector<slotId_t> const*
TaskManager_t::terminatePriorityExecutions() noexcept
{
    // Detect subtask with less exec time.
    slots_used_.clear();
    TIME less_exec_time { std::numeric_limits<TIME>::max() };
    //Subtask_t* subtask_more_priority{nullptr};
    std::vector<Subtask_t*>& priority_execs { getPriorityExecutions() };
    for (auto& subtask_prior : priority_execs){
        if (subtask_prior->lapse_ < less_exec_time) {
            less_exec_time = subtask_prior->lapse_;
            //subtask_more_priority = subtask_prior;
        }
    }
    //std::cout<<"priors: "<<priority_execs.size()<<" "<<less_exec_time<<'\n';

    // Subtract time and eliminate what remains at 0.
    TIME t_zero {0};
    for (auto& [_, buffer] : buffersExec_){
        if (!buffer.empty())
        {
            Subtask_t& subtask { *buffer.begin().base() };
            subtask.lapse_ -= less_exec_time;
            if (subtask.lapse_ == t_zero)
            {
                slotId_t slot_id_used { subtask.slot_id };
                getSlot(slot_id_used).setActive(false);
                getSlot(slot_id_used).setUsing(false);
                buffer.erase(buffer.begin());
                slots_used_.push_back(slot_id_used);
                
                if ( buffer.size() ) { // Execution pending.
                    Subtask_t& subtask { *buffer.begin().base() };
                    slotId_t slot_id { subtask.slot_id };
                    getSlot(slot_id).setActive(true); // setUsing(true) is already.
                }
            }
        }
    }
    return &slots_used_;

    //slotId_t slot_id_used { getPriorityExecution().slot_id };
    //getSlot(slot_id_used).setActive(false);
    //getSlot(slot_id_used).setUsing(false);
    //bufferExec_.erase(bufferExec_.begin());
//
    //if (executionPending()) {
    //    slotId_t slot_id { getPriorityExecution().slot_id };
    //    getSlot(slot_id).setActive(true);
    //}
    //return slot_id_used;
}

std::size_t  
TaskManager_t::pendingExecutions() const noexcept
{
    std::size_t n_exec_pending {0};
    for (auto& [id_core, buffer] : buffersExec_){
        auto buffize {buffer.size()};
        if (buffize) std::cout<<"core "<<id_core<<": "<<buffize<<'\n';
        n_exec_pending += buffize;//buffer.size();
    }
    
    return n_exec_pending;
    //return bufferExec_.size();
}

///////////////////////////////////////////////////////////////////////////////////

/*Subtask_t const& 
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
    getSlot(slot_id_used).setActive(false);
    getSlot(slot_id_used).setUsing(false);
    bufferExec_.erase(bufferExec_.begin());

    if (executionPending()) {
        slotId_t slot_id { getPriorityExecution().slot_id };
        getSlot(slot_id).setActive(true);
    }

    return slot_id_used;
}

std::size_t  
TaskManager_t::executionPending() const noexcept
{
    return bufferExec_.size();
}*/

} // namespace FLINK