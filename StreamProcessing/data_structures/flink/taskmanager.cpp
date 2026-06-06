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

namespace FLINK {

[[nodiscard]] slotId_t 
TaskManager_t::reserveSlot(operId_t const& oper_id) noexcept
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

std::map<slotId_t, TaskSlot_t> const&
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
    operId_t const& operid            { slot.getOperator() };
    double          exec_lapse        {};
    double          prod_improd_lapse {}; // Productive + Improductive time.
    
    do {
        exec_lapse        = jobMan.getTimeExecution(operid);            // Get avg time excecution of some distribution.
        prod_improd_lapse = exec_lapse * jobMan.getDegradationFactor(); // Increase the time to degrade the system
    } 
    while (prod_improd_lapse < 0 || prod_improd_lapse >= std::numeric_limits<int>::max());

    // Accumulate operator busy time (to sec).
    jobMan.accumBusyTime(operid, exec_lapse / 1000000000000);
    //jobMan.getOperatorProperties(operid).accum_busy_time_ += (prod_improd_lapse / 1000000000000); // to sec.
    //if (operid == "sourcedatagen1")
    //    std::cout<<operid<<", slot: "<<slot_id<<", acumm: "<<jobMan.getOperatorProperties(operid).accum_busy_time_ <<'\n';

    // Time with degradation.
    int lapse_ps { static_cast<int>(std::round(prod_improd_lapse)) };

    // Descompose time
    int lapse_hr  = lapse_ps / 3'600'000'000'000'000;   // 3.6e15
    lapse_ps     %=  3'600'000'000'000'000;
    int lapse_min = lapse_ps / 60'000'000'000'000;      // 6e13
    lapse_ps     %= 60'000'000'000'000;
    int lapse_s   = lapse_ps / 1'000'000'000'000;       // 1e12
    lapse_ps     %= 1'000'000'000'000;
    int lapse_ms  = lapse_ps / 1'000'000'000;           // 1e9
    lapse_ps     %= 1'000'000'000;
    int lapse_us  = lapse_ps / 1'000'000;               // 1e6
    lapse_ps     %= 1'000'000;
    int lapse_ns  = lapse_ps / 1'000;                   // 1e3
    lapse_ps     %= 1'000;

    //std::cout<<"Lapse: "<< lapse_ps <<", hr: "<<lapse_hr<<" min: "<<lapse_min<<" s: "<<lapse_s<<" ms: "<<lapse_ms<<" us: "<<lapse_us<<" ns: "<<lapse_ns<<" ps: "<<lapse_ps<<"\n";
    TIME timeExec = {lapse_hr,lapse_min,lapse_s,lapse_ms,lapse_us,lapse_ns,lapse_ps}; // hrs::mins:secs:mills:micrs::nns:(pcs)::fms
    
    ExecutionBuffer_t*      bufferLessCongestion { nullptr };
    uint32_t                id_core_select       { 0 };
    std::size_t             n_exec_less          { std::numeric_limits<uint32_t>::max() };

    // Search core buffer with less congestion.
    for (auto& [id_core, buffer] : this->exec_buffers_)
    {
        auto n_exec { buffer.size() };
        if (n_exec <= n_exec_less) 
        {
            n_exec_less          = n_exec;
            bufferLessCongestion = &buffer;
            id_core_select       = id_core;
        }
    }

    // Add execution to buffer.
    bufferLessCongestion->emplace({mssg_id, slot_id, timeExec});
    slot.setUsing(true);

    // Slot added recently is priority? set active in execution.
    for (auto& priority_exec : getPriorityExecutions()){
        if (priority_exec->slot_id_ == slot_id){           
            slot.setActive(true);                         
            break;
        }
    }
}

std::vector<Subtask_t*>& 
TaskManager_t::getPriorityExecutions() noexcept
{
    this->priority_execs_.clear(); // Keep capacity.
    for (auto& [id_core, buffer] : this->exec_buffers_)
    {
        if (!buffer.empty())
            this->priority_execs_.push_back(&buffer.front()); // Collect priority executions.
    }
    return this->priority_execs_;
}


std::vector<slotId_t> const&
TaskManager_t::terminatePriorityExecutions() noexcept
{
    this->slots_used_.clear(); // Keep capacity.
    TIME                     less_exec_time { std::numeric_limits<TIME>::max() };
    std::vector<Subtask_t*>& priority_execs { getPriorityExecutions()          };

    // Detect subtask with less exec time.
    for (auto& subtask_prior : priority_execs){
        if (subtask_prior->lapse_ < less_exec_time)
            less_exec_time = subtask_prior->lapse_;
    }
    //std::cout<<"prior execs: "<<priority_execs.size()<<'\n';

    // CORE PARALLELISM: Subtract the least amount of time from priority executions and eliminate what remains at 0.
    TIME t_zero {0};
    for (auto& [_, buffer] : this->exec_buffers_){
        if ( !buffer.empty() )
        {
            // Subtract shortest time execution.
            Subtask_t& subtask { buffer.front() };
            subtask.lapse_ -= less_exec_time;
            
            if (subtask.lapse_ == t_zero) // Finished?
            {
                // Free slot.
                slotId_t slot_id_used { subtask.slot_id_ };
                getSlot(slot_id_used).setActive(false);
                getSlot(slot_id_used).setUsing(false);

                //buffer.erase(buffer.begin()); // Very slow !!
                buffer.pop();

                this->slots_used_.push_back(slot_id_used);
                
                if ( buffer.size() ) { // Execution pending.
                    Subtask_t& subtask { buffer.front() }; // Get priority.
                    slotId_t   slot_id { subtask.slot_id_ };
                    getSlot(slot_id).setActive(true); // setUsing(true) is already in buffer.
                }
            }
        }
    }
    return this->slots_used_;
}

std::size_t  
TaskManager_t::pendingExecutions() const noexcept
{
    std::size_t n_exec_pending {0};
    this->current_execs_ = 0;
    for (auto& [id_core, buffer] : this->exec_buffers_)
    {
        auto buffize { buffer.size() };
        if (buffize){
            ++current_execs_;
            n_exec_pending += buffize;//buffer.size();
        }
        //std::cout<<"core "<<id_core<<": "<<buffize<<'\n';
    }
    return n_exec_pending;
}

std::size_t 
TaskManager_t::executing() const noexcept
{
    return current_execs_;
}

///////////////////////////////////////////////////////////////////////////////////

} // namespace FLINK