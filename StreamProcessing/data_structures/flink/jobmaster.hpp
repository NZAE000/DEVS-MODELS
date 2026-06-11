/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Jobmaster definition
*/
#pragma once
#include<map>
#include<vector>
#include<string>
#include "typealiases.hpp"
#include "../operator_location.hpp"

namespace FLINK {

struct JobMaster_t {

    explicit JobMaster_t() {}

//Methods
                                                    void addLocation(operId_t const, nodeId_t, slotId_t)  noexcept;
    [[nodiscard]] std::vector<OperatorLocation_t> const& getLocations(operId_t const)               const noexcept;

private:
    std::map<operId_t, std::vector<OperatorLocation_t>> operLocations_ {};

};

} // namespace FLINK 