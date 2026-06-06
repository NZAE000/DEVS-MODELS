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

namespace FLINK {


struct TaskSlot_t {

    //explicit TaskSlot_t() noexcept = default;
    explicit TaskSlot_t(operId_t const& oper_id) noexcept
    : operator_id_{oper_id} 
    {
        buffer_.reserve(TUPLES_CAPACITY);
        head_ = &buffer_[0];
    } 

// Method 
    constexpr void pushTuple(mssgId_t id) noexcept 
    { 
        if ( buffer_.size() == buffer_.capacity() 
          && active_size_ > buffer_.capacity() / 2 )
        {
            buffer_.erase(buffer_.begin(), buffer_.begin() + active_size_);
            active_size_ = 0;
            head_        = &buffer_[0];
            std::cout<<"aca2\n";
        }
        buffer_.emplace_back(id);
    }

    constexpr mssgId_t popTuple() noexcept 
    { 
        mssgId_t id = *head_;
        ++active_size_; ++head_;
        return id;
    }

    constexpr std::size_t  nTuples()       const noexcept { return buffer_.size() - active_size_; }
    constexpr bool         isUsing()       const noexcept { return using_;       }
    constexpr void         setUsing(bool state)  noexcept { using_ = state;      }
    constexpr bool         isActive()      const noexcept { return active_;      }
    constexpr void         setActive(bool state) noexcept { active_= state;      }
    constexpr bool         pendingTuples() const noexcept { return nTuples();    }
    operId_t const&        getOperator()   const noexcept { return operator_id_; }

private:
    std::vector<mssgId_t>   buffer_        {};
    operId_t const&         operator_id_;
    bool                    using_         { false   };
    bool                    active_        { false   };
    mssgId_t*               head_          { nullptr };
    std::size_t             active_size_   {};

    inline static constexpr std::size_t TUPLES_CAPACITY {10000000};
};


} // namespace FLINK