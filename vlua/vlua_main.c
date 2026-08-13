/*
 * vlua -- vaporOS's Lua host. Creates its own Lua state (doesn't touch
 * NuttX's own `lua` command) and always registers the "vapor" table
 * before running anything, so every script run through vlua has it
 * available -- this program IS the vapor-enabled runtime, not a
 * separate thing that later gets pointed at one.
 */

#include <nuttx/config.h>
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "vapor_core.h"

/* Runs with no arguments, so `vlua` alone proves the binding works
 * without needing a script file to already exist on the filesystem.
 */
static const char demo_script[] =
  "vapor.print(\"Hello from vaporOS's own Lua API!\")\n"
  "vapor.print(\"1 + 2 =\", 1 + 2)\n";

/*
 * Sets the global `arg` table the same way the real `lua` CLI does:
 * arg[1], arg[2], ... are the script's own arguments (argv[2] onward
 * here, since argv[1] is the script path itself). Without this, a
 * vapor script has no way to receive command-line arguments at all --
 * fine for a demo, not fine for "build any kind of program".
 */
static void vlua_setup_args(lua_State *L, int argc, FAR char *argv[])
{
  int i;

  lua_newtable(L);

  for (i = 2; i < argc; i++)
    {
      lua_pushstring(L, argv[i]);
      lua_rawseti(L, -2, i - 1);
    }

  lua_setglobal(L, "arg");
}

int main(int argc, FAR char *argv[])
{
  lua_State *L = luaL_newstate();

  if (L == NULL)
    {
      fprintf(stderr, "vlua: could not create Lua state\n");
      return 1;
    }

  luaL_openlibs(L);

  lua_newtable(L);
  lua_setglobal(L, "vapor");

  vapor_core_register(L);

  int status;

  if (argc > 1)
    {
      vlua_setup_args(L, argc, argv);
      status = luaL_dofile(L, argv[1]);
    }
  else
    {
      status = luaL_dostring(L, demo_script);
    }

  if (status != LUA_OK)
    {
      fprintf(stderr, "vlua: %s\n", lua_tostring(L, -1));
      lua_close(L);
      return 1;
    }

  lua_close(L);
  return 0;
}
