#ifndef VAPOR_CORE_H
#define VAPOR_CORE_H

#include "lua.h"

/*
 * Registers the "vapor" table's portable core -- everything here works
 * identically regardless of what vaporOS is actually running on top of
 * (sim, real hardware, whatever comes later). Nothing in this file
 * touches a specific peripheral or device path; that's what later
 * modules (vapor_gpio.c, a future vapor_screen.c, etc.) are for --
 * each gets its own register function, called alongside this one from
 * vlua_main.c, all adding onto the same "vapor" global table.
 */
void vapor_core_register(lua_State *L);

#endif
