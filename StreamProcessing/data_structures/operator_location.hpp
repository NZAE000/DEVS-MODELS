/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Operator location data definition
*/

#pragma once
#include<cstdint>
#include<iostream>


/*******************************************/
/************ OperatorLocation_t ***********/
/*******************************************/
struct OperatorLocation_t {
  OperatorLocation_t(uint32_t mssgId, uint32_t nid, uint32_t sid) 
    :mssg_id{mssgId}, node_id{nid}, slot_id{sid} {}

    uint32_t mssg_id{};
    uint32_t node_id{};
    uint32_t slot_id{};
};

/***************************************************/
/************* Output stream ************************/
/***************************************************/
std::ostream& operator<<(std::ostream& os, const OperatorLocation_t& loc);

/***************************************************/
/************* Input stream ************************/
/***************************************************/
std::istream& operator>>(std::istream& is, OperatorLocation_t& loc);