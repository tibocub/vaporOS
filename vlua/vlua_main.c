/*
 * vlua -- the first slice of vaporOS's ComputerCraft-inspired Lua API.
 *
 * Creates its own Lua state (doesn't touch NuttX's own `lua` command)
 * and exposes a "vapor" table to scripts, alongside Lua's normal
 * standard library. Two functions to start:
 *
 *   vapor.print(...)  -- print args space-separated, newline at end
 *   vapor.read()       -- read one line from stdin, nil on EOF
 *
 * Deliberately not touching Lua's own global print()/io.read() --
 * "vapor" is meant to grow into the real high-level API (screens,
 * peripherals, etc., ComputerCraft-style), kept separate from Lua's
 * own standard library rather than replacing pieces of it.
 */

#include <nuttx/config.h>
#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static int vapor_print(lua_State *L)
{
  int argc = lua_gettop(L);
  int i;

  for (i = 1; i <= argc; i++)
    {
      const char *s = lua_tostring(L, i);

      if (i > 1)
        {
          fputc(' ', stdout);
        }

      fputs(s != NULL ? s : "nil", stdout);
    }

  fputc('\n', stdout);
  return 0;
}

static int vapor_read(lua_State *L)
{
  char buf[128];

  if (fgets(buf, sizeof(buf), stdin) == NULL)
    {
      lua_pushnil(L);
      return 1;
    }

  size_t len = strlen(buf);

  if (len > 0 && buf[len - 1] == '\n')
    {
      buf[len - 1] = '\0';
    }

  lua_pushstring(L, buf);
  return 1;
}

static const luaL_Reg vapor_funcs[] =
{
  { "print", vapor_print },
  { "read",  vapor_read },
  { NULL,    NULL }
};

/* Runs with no arguments, so `vlua` alone proves the binding works
 * without needing a script file to already exist on the filesystem.
 */
static const char demo_script[] =
  "vapor.print(\"Hello from vaporOS's own Lua API!\")\n"
  "vapor.print(\"1 + 2 =\", 1 + 2)\n";

int main(int argc, FAR char *argv[])
{
  lua_State *L = luaL_newstate();

  if (L == NULL)
    {
      fprintf(stderr, "vlua: could not create Lua state\n");
      return 1;
    }

  luaL_openlibs(L);

  luaL_newlib(L, vapor_funcs);
  lua_setglobal(L, "vapor");

  int status;

  if (argc > 1)
    {
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
