/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Taskslot implementation
*/
#pragma once
#include<string>
#include "typealiases.hpp"


namespace FLINK {


struct TaskSlot_t {

    //explicit TaskSlot_t() noexcept = default;
    explicit TaskSlot_t(operId_t const& oper_id) noexcept
    : operator_id_{oper_id} {} 

// Methods
    operId_t const& getOperator()     const noexcept { return operator_id_;    }
    constexpr void pushTuple()              noexcept { ++buffer_;              }
    constexpr void popTuple()               noexcept { if (buffer_) --buffer_; }
    constexpr uint32_t nTuples()      const noexcept { return buffer_;         }
    constexpr bool isUsing()          const noexcept { return using_;          }
    constexpr void setUsing(bool state)     noexcept { using_ = state;         }
    constexpr bool isActive()         const noexcept { return active_;         }
    constexpr void setActive(bool state)    noexcept { active_= state;         }
    constexpr bool pendingTuples()    const noexcept { return nTuples();       }

private:
    operId_t const& operator_id_;
    bool using_{false};
    bool active_{false};
    uint32_t buffer_{};
};


} // namespace FLINK