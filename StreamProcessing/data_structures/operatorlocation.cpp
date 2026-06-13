/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Operator location data implementation
*/

#include "operatorlocation.hpp"

/***************************************************/
/************* Output stream ************************/
/***************************************************/
std::ostream& operator<<(std::ostream& os, const OperatorLocation_t& loc) {
  //os << loc.packet << " " << loc.bit;
  os << loc.mssg_id_ <<" "<<loc.node_id_ <<" "<< loc.slot_id_;
  return os;
}

/***************************************************/
/************* Input stream ************************/
/***************************************************/
std::istream& operator>>(std::istream& is, OperatorLocation_t& loc) {
  is >> loc.mssg_id_ >> loc.node_id_ >> loc.slot_id_;
  //is >> loc.bit;
  return is;
}