/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskmanager implementation
*/
#include "taskmanager.hpp"
#include "jobmanager.hpp"
#include<algorithm>
#include<iostream>


namespace streamprcss {
    namespace flink {

    [[nodiscard]] slotId_t 
    TaskManager_t::reserveSlot(operId_t const oper_id) noexcept
    {
        auto pair = taskslots_.insert(std::pair<slotId_t, operId_t const&>(next_slot_id_++, oper_id));
        return pair.first->first;
    }

    TaskSlot_t const& 
    TaskManager_t::getSlot(slotId_t id) const noexcept
    {
        auto taskSlot_iter = taskslots_.find(id);
        return taskSlot_iter->second;
    }
    TaskSlot_t&       
    TaskManager_t::getSlot(slotId_t id) noexcept
    {
        auto& slot = const_cast<TaskManager_t const*>(this)->getSlot(id);
        return *const_cast<TaskSlot_t*>(&slot);
    }

    std::unordered_map<slotId_t, TaskSlot_t> const&
    TaskManager_t::getSlots() const noexcept
    {
        return taskslots_;
    }

    void 
    TaskManager_t::scheduleExec(mssgId_t mssg_id, slotId_t slot_id, JobManager_t& jobMan) noexcept
    {
        TaskSlot_t& slot = getSlot(slot_id); // Get task slot.

        if (slot.isUsing()) slot.pushTuple(mssg_id); // Queuing on buffer.
        else 
            createSubTask(jobMan, slot, mssg_id, slot_id);
    }

    void 
    TaskManager_t::checkQueuedExecution(slotId_t slot_id, JobManager_t& jobMan) noexcept
    {
        TaskSlot_t& slot = getSlot(slot_id); // Get task slot.
        if (slot.pendingTuples())            // Has pending tuples to execute? 
        {
            mssgId_t mssg_id = slot.popTuple();  // Remove tuple from slot buffer.
            createSubTask(jobMan, slot, mssg_id, slot_id);

        } //else slot.setExecution(false);
    }

    void 
    TaskManager_t::createSubTask(JobManager_t& jobMan, TaskSlot_t& slot, mssgId_t mssg_id, slotId_t slot_id) noexcept 
    {    
        operId_t const& operid     { slot.getOperator() };
        TIME     exec_lapse        {};
        TIME     prod_improd_lapse {}; // Productive + Improductive time.
        
        do {
            exec_lapse        = jobMan.getTimeExecution(operid);            // Get avg time excecution of some distribution.
            prod_improd_lapse = exec_lapse * jobMan.getDegradationFactor(); // Increase the time to degrade the system
        } 
        while (prod_improd_lapse < 0 || prod_improd_lapse >= std::numeric_limits<int>::max());

        // Accumulate operator busy time (to sec).
        jobMan.accumBusyTime(operid, exec_lapse / 1000000000000);
        
        // Search core buffer with less congestion.
        ExecutionBuffer_t* less_loaded_buff { nullptr };
        std::size_t        n_exec_less      { std::numeric_limits<uint32_t>::max() };
        coreId_t           core_id_select   {};
        for (coreId_t core_id=0; core_id < this->n_cores_; ++core_id)
        {
            auto& buffer { this->exec_buffers_[core_id] };
            auto n_exec  { buffer.size() };
            if (n_exec <= n_exec_less) 
            {
                n_exec_less      = n_exec;
                less_loaded_buff = &buffer;
                core_id_select   = core_id;
            }
        }

        // Add subtask to less loaded buffer.
        less_loaded_buff->emplace({mssg_id, slot_id, prod_improd_lapse});
        slot.setUsing(true);
        ++this->pending_execs_; // Update!

        // Slot added recently is priority? Set active in execution.
        if (less_loaded_buff->size() == 1)
        {
            slot.setActive(true);
            less_loaded_buff->activateSubtask(core_id_select, this->active_subtasks_.size());    // Activate the subprocess with stored core id and position index.
            this->active_subtasks_.emplace_back(&less_loaded_buff->getActiveSubtask());          // Add active subtask to priorities.
            ++this->current_execs_; // Update!
        }
    }


    std::vector<slotId_t> const&
    TaskManager_t::terminateActiveExecutions() noexcept
    {
        //std::cout<<"aca\n";
        TIME less_exec_time {std::numeric_limits<TIME>::max()};
        TIME lapse          {};

        // Detect subtask with less exec time.
        for (auto const& buffer : this->exec_buffers_){   
            if ( !buffer.empty() )
            {
                lapse = buffer.front().lapse_;
                if (lapse < less_exec_time)
                    less_exec_time = lapse;
            }
        }

        // CORE PARALLELISM: Subtract the least amount of time from priority executions and eliminate what remains at 0.
        TIME const  t_zero       {0};
        slotId_t    slot_id_used {};
        this->slots_used_.clear(); // Keep capacity.

        for (coreId_t core_id=0; core_id < this->n_cores_; ++core_id)
        {
            auto& buffer { this->exec_buffers_[core_id] };
            if ( !buffer.empty() )
            {
                // Subtract the shortest execution time from the active subtask.
                ActiveSubtask_t& active_subtask = buffer.getActiveSubtask();
                Subtask_t* subtask              = active_subtask.subtask_;
                subtask->lapse_                -= less_exec_time;
                
                if (subtask->lapse_ == t_zero) // Finished?
                {
                    // Free slot.
                    slot_id_used     = subtask->slot_id_;
                    TaskSlot_t& slot = getSlot(slot_id_used);
                    slot.setActive(false);
                    slot.setUsing(false);
                    this->slots_used_.emplace_back(slot_id_used);
                    
                    // Delete execution from priorities.
                    uint32_t idx_priority { active_subtask.idx_priority_ };
                    if (idx_priority != this->active_subtasks_.size() - 1)  // Isn't the end?, copy the end to current.
                    {  
                        this->active_subtasks_[idx_priority] = this->active_subtasks_.back();
                        this->active_subtasks_[idx_priority]->idx_priority_= idx_priority; // Update!
                    }
                    this->active_subtasks_.pop_back(); // And drop last.

                    //buffer.erase(buffer.begin()); // Very slow !!
                    buffer.pop();
                    
                    // Is there queued execution?
                    if ( buffer.size() ) 
                    {
                        Subtask_t& subtask { buffer.front() };                                // Get priority.
                        getSlot(subtask.slot_id_).setActive(true);                            // setUsing(true) is already in buffer.
                        buffer.activateSubtask(core_id, this->active_subtasks_.size());       // Activate the subprocess with stored core id and position index.
                        this->active_subtasks_.emplace_back(&buffer.getActiveSubtask());      // Add active subtask to priorities.
                    }
                    else --this->current_execs_; // Update!

                    --this->pending_execs_; // Update!
                }
            }
        }
        return this->slots_used_;
    }


    std::vector<ActiveSubtask_t*>& 
    TaskManager_t::getActiveExecutions() noexcept
    {
        return this->active_subtasks_;
    }

    std::size_t  
    TaskManager_t::pendingExecutions() const noexcept
    {
        return this->pending_execs_;
    }

    std::size_t 
    TaskManager_t::executing() const noexcept
    {
        return this->current_execs_;
    }

    ///////////////////////////////////////////////////////////////////////////////////

    } // namespace flink
} // namespace streamprcss