#pragma once
#include "typealiases.hpp"

//Time class header
#include <NDTime.hpp>
using TIME = NDTime;
#include<iostream>

namespace FLINK {


struct Subtask_t {

    Subtask_t(mssgId_t mssgid, slotId_t sid, TIME const& time)
    : mssg_id_{mssgid}, slot_id_{sid}, lapse_{time} {}

    mssgId_t mssg_id_ {};
    slotId_t slot_id_ {};
    TIME     lapse_   {};
};

struct ExecutionBuffer_t {

    explicit ExecutionBuffer_t(std::size_t n_subtask)
    {
        subtasks_.reserve(n_subtask);
        head_ = &subtasks_[0];
    }

    void emplace(Subtask_t&& t)
    {
        if ( subtasks_.size() == subtasks_.capacity() 
          && active_size_ > subtasks_.capacity() / 2 )
        {
            subtasks_.erase(subtasks_.begin(), subtasks_.begin() + active_size_);
            active_size_ = 0;
            head_        = &subtasks_[0];
            std::cout<<"aca\n";
        }

        subtasks_.emplace_back(std::move(t));
    }

    Subtask_t&       front()                     { return *head_; }
    Subtask_t const& front()      const          { return *head_; }
    void             pop()              noexcept { ++active_size_; ++head_; }
    bool             empty()      const noexcept { return active_size_ == subtasks_.size(); }
    size_t           size()       const          { return subtasks_.size() - active_size_;  }
         
private:
    std::vector<Subtask_t> subtasks_        {};
    Subtask_t*             head_            {nullptr};
    std::size_t            active_size_     {};
};


} // namespace flink