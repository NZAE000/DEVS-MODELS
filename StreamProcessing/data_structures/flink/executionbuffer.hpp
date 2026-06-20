#pragma once
#include "typealiases.hpp"
#include <vector>


namespace streamprcss {
    namespace flink {

    struct Subtask_t {

        Subtask_t(mssgId_t mssgid, slotId_t sid, TIME const time)
        : mssg_id_{mssgid}, slot_id_{sid}, lapse_{time} {}

        mssgId_t mssg_id_ {};
        slotId_t slot_id_ {};
        TIME     lapse_   {};
    };

    struct ActiveSubtask_t {

        //explicit ActiveSubtask_t() = default;

        Subtask_t* subtask_       {nullptr};
        coreId_t   core_id_       {};
        uint32_t   idx_priority_  {};
    };

    struct ExecutionBuffer_t {

        explicit ExecutionBuffer_t(std::size_t subtask_capacity)
        {
            prepared_subtasks_.reserve(subtask_capacity);
        }

        void emplace(Subtask_t&& subtask)
        {
            if (prepared_subtasks_.size() == prepared_subtasks_.capacity())
            {
                if (head_index_ > prepared_subtasks_.capacity() * COMPACT_RATIO_)
                {
                    prepared_subtasks_.erase(prepared_subtasks_.begin(), prepared_subtasks_.begin() + head_index_);
                    head_index_ = 0;
                    //std::cout<<"aca\n";
                }
                else {
                    // Exceptional growth.
                    prepared_subtasks_.reserve(prepared_subtasks_.capacity() * 1.5);
                }
                active_subtask_.subtask_ = &this->front();
            }
            prepared_subtasks_.emplace_back(std::move(subtask));
        }

        void activateSubtask(coreId_t core_id_, uint32_t index) noexcept
        {
            active_subtask_.core_id_      = core_id_;
            active_subtask_.idx_priority_ = index;
            active_subtask_.subtask_      = &this->front();
            //std::cout<<"inx: "<<index<<'\n';
        }

        ActiveSubtask_t&       getActiveSubtask()       noexcept { return this->active_subtask_; }
        ActiveSubtask_t const& getActiveSubtask() const noexcept { return this->active_subtask_; }

        Subtask_t&            front()                 { return prepared_subtasks_[head_index_];          }
        Subtask_t const&      front()  const          { return prepared_subtasks_[head_index_];          }
        constexpr void        pop()          noexcept { ++head_index_;                                   }
        constexpr std::size_t size()   const          { return prepared_subtasks_.size() - head_index_;  }
        constexpr bool        empty()  const noexcept { return head_index_ == prepared_subtasks_.size(); }
        
            
    private:

        ActiveSubtask_t        active_subtask_    {};
        std::vector<Subtask_t> prepared_subtasks_ {};
        std::size_t            head_index_        {};

        inline static constexpr double COMPACT_RATIO_ { 0.75 };
    };


    } // namespace flink
} // namespace streamprcss