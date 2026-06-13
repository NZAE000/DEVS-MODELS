/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Operator location data definition
*/

#pragma once
#include <cstdint>
#include <iostream>


/*******************************************/
/************ OperatorLocation_t ***********/
/*******************************************/
struct OperatorLocation_t {

  OperatorLocation_t(uint32_t mssgId, uint32_t nid, uint32_t sid) 
    : mssg_id_{mssgId}, node_id_{nid}, slot_id_{sid} {}

    uint32_t mssg_id_ {};
    uint32_t node_id_ {};
    uint32_t slot_id_ {};
};

/***************************************************/
/************* Output stream ************************/
/***************************************************/
std::ostream& operator<<(std::ostream& os, const OperatorLocation_t& loc);

/***************************************************/
/************* Input stream ************************/
/***************************************************/
std::istream& operator>>(std::istream& is, OperatorLocation_t& loc);