/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Operator location data implementation
*/

#include "operator_location.hpp"

/***************************************************/
/************* Output stream ************************/
/***************************************************/
std::ostream& operator<<(std::ostream& os, const OperatorLocation_t& loc) {
  //os << loc.packet << " " << loc.bit;
  os << loc.node_id <<" "<< loc.slot_id;
  return os;
}

/***************************************************/
/************* Input stream ************************/
/***************************************************/
std::istream& operator>>(std::istream& is, OperatorLocation_t& loc) {
  is >> loc.node_id >> loc.slot_id;
  //is >> loc.bit;
  return is;
}