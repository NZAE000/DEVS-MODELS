/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Message data imlementation
*/

#include "message.hpp"

/***************************************************/
/************* Output stream ************************/
/***************************************************/
std::ostream& operator<<(std::ostream& os, const Message_t& msg) {
  //os << msg.packet << " " << msg.bit;
  os << msg.id_;
  return os;
}

/***************************************************/
/************* Input stream ************************/
/***************************************************/
std::istream& operator>>(std::istream& is, Message_t& msg) {
  is >> msg.id_;
  //is >> msg.bit;
  return is;
}
