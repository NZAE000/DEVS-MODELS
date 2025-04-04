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

    explicit TaskSlot_t() noexcept = default;
    explicit TaskSlot_t(operId_t const& oper_id) noexcept
    : operator_id{oper_id} {} 

// Methods
    operId_t const& getOperator()     const noexcept { return operator_id; }
    constexpr void pushTuple()              noexcept { ++buffer; }
    constexpr void popTuple()               noexcept { if (buffer) --buffer; }
    constexpr uint32_t nTuples()      const noexcept { return buffer; }
    constexpr bool isRunnig()         const noexcept { return busy; }
    constexpr void setExecution(bool state) noexcept { busy = state; }
    bool pendingTuples()              const noexcept { return nTuples(); }

private:
    operId_t operator_id{};
    bool busy{false};
    uint32_t buffer{};
};


} // namespace FLINK