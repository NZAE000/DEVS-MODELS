/**
* Eliezer Andrés Zúñiga Nanjari
* Universidad de Valparaíso
*
* Message data definition
*/

#ifndef __MESSAGE__
#define __MESSAGE__

#include <assert.h>
#include <iostream>
#include <string>
#include <cstdint>


/*******************************************/
/**************** Message_t ****************/
/*******************************************/
struct Message_t {
  Message_t() = default;
  Message_t(uint32_t id)
   : id_(id){}

  uint32_t id_{};
};

/***************************************************/
/************* Output stream ************************/
/***************************************************/
std::ostream& operator<<(std::ostream& os, const Message_t& msg);

/***************************************************/
/************* Input stream ************************/
/***************************************************/
std::istream& operator>>(std::istream& is, Message_t& msg);


#endif // __MESSAGE__