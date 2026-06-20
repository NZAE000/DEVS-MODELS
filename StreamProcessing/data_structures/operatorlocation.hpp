/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Operator location data definition
*/

#pragma once
#include <cstdint>
#include <iostream>
#include "flink/typealiases.hpp"

/*******************************************/
/************ OperatorLocation_t ***********/
/*******************************************/
struct OperatorLocation_t {

  OperatorLocation_t(uint32_t mssgId, uint32_t nid, uint32_t sid) 
    : mssg_id_{mssgId}, node_id_{nid}, slot_id_{sid} {}

    streamprcss::flink::mssgId_t mssg_id_ {};
    streamprcss::flink::nodeId_t node_id_ {};
    streamprcss::flink::slotId_t slot_id_ {};
};

/***************************************************/
/************* Output stream ************************/
/***************************************************/
std::ostream& operator<<(std::ostream& os, const OperatorLocation_t& loc);

/***************************************************/
/************* Input stream ************************/
/***************************************************/
std::istream& operator>>(std::istream& is, OperatorLocation_t& loc);
