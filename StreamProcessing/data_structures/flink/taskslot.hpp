/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskslot implementation
*/
#pragma once
#include <string>
#include <vector>
#include "typealiases.hpp"
#include <iostream>


namespace streamprcss {
    namespace flink {

    struct TaskSlot_t {

        //explicit TaskSlot_t() noexcept = default;
        explicit TaskSlot_t(operId_t const oper_id) noexcept
        : operator_id_{oper_id} 
        {
            buffer_.reserve(TUPLES_CAPACITY);
        } 

    // Method 
        constexpr void pushTuple(mssgId_t mssg) noexcept 
        { 
            if (buffer_.size() == buffer_.capacity())
            {
                if (head_index_ > buffer_.capacity() * COMPACT_RATIO)
                {
                    buffer_.erase(buffer_.begin(), buffer_.begin() + head_index_);
                    head_index_ = 0;
                    //std::cout<<"aca\n";
                }
                else {
                    // Exceptional growth.
                    buffer_.reserve(buffer_.capacity() * 1.5);
                }
            }
            buffer_.emplace_back(mssg);
        }

        constexpr mssgId_t popTuple() noexcept 
        { 
            mssgId_t id = buffer_[head_index_];
            ++head_index_;
            return id;
        }

        constexpr std::size_t  nTuples()       const noexcept { return buffer_.size() - head_index_; }
        constexpr bool         isUsing()       const noexcept { return using_;       }
        constexpr void         setUsing(bool state)  noexcept { using_ = state;      }
        constexpr bool         isActive()      const noexcept { return active_;      }
        constexpr void         setActive(bool state) noexcept { active_= state;      }
        constexpr bool         pendingTuples() const noexcept { return nTuples();    }
        operId_t const&        getOperator()   const noexcept { return operator_id_; }

    private:
        std::vector<mssgId_t>   buffer_        {};
        operId_t const          operator_id_;
        bool                    using_         { false };
        bool                    active_        { false };
        std::size_t             head_index_    {};

        inline static constexpr std::size_t TUPLES_CAPACITY { 1000000 };
        inline static constexpr double      COMPACT_RATIO   { 0.75    };
    };


    } // namespace flink
} // namespace streamprcss