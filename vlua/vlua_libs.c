/*
 * vlua_libs.c -- third-party Lua C libraries, selected at build time
 * (VAPOROS_VLUA_* in vlua/Kconfig). vaporOS has no dynamic linking, so
 * instead of package.cpath they are linked in and found through
 * package.preload: require("lfs") works exactly as on a desktop Lua.
 */

#include <nuttx/config.h>

#include "lua.h"
#include "lauxlib.h"

#ifdef VLUA_LFS
int luaopen_lfs(lua_State *L);
#endif
#ifdef VLUA_LPEG
int luaopen_lpeg(lua_State *L);
#endif
#ifdef VLUA_CJSON
int luaopen_cjson(lua_State *L);
#endif
#ifdef VLUA_SOCKET
int luaopen_vsock(lua_State *L);
#endif
#ifdef VLUA_TLS
int luaopen_vtls(lua_State *L);
#endif

static const luaL_Reg g_libs[] =
{
#ifdef VLUA_LFS
  {"lfs", luaopen_lfs},
#endif
#ifdef VLUA_LPEG
  {"lpeg", luaopen_lpeg},
#endif
#ifdef VLUA_CJSON
  {"cjson", luaopen_cjson},
#endif
#ifdef VLUA_SOCKET
  {"vsock", luaopen_vsock},
#endif
#ifdef VLUA_TLS
  {"vtls", luaopen_vtls},
#endif
  {NULL, NULL}
};

void vlua_libs_register(lua_State *L)
{
  const luaL_Reg *lib;

  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  for (lib = g_libs; lib->name != NULL; lib++)
    {
      lua_pushcfunction(L, lib->func);
      lua_setfield(L, -2, lib->name);
    }

  lua_pop(L, 1);
}
