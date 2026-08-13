/*
 * vapor's portable core: print/read/write/sleep/time. Nothing here
 * assumes any particular hardware -- if it wouldn't work identically
 * on a plain Linux box, it doesn't belong in this file.
 *
 * Registration pattern (this matters once a second module exists):
 * vlua_main.c creates an empty global "vapor" table once, then calls
 * each module's own *_register(L), which fetches that existing table
 * via lua_getglobal and adds its own fields with lua_setfield -- never
 * luaL_newlib/lua_setglobal here, since that would overwrite whatever
 * an earlier module already registered.
 */

#include <nuttx/config.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#include "lua.h"
#include "lauxlib.h"

#include "vapor_core.h"

/****************************************************************************
 * vapor.print(...) -- print args space-separated, newline at end.
 ****************************************************************************/

static int vapor_print(lua_State *L)
{
  int argc = lua_gettop(L);
  int i;

  for (i = 1; i <= argc; i++)
    {
      const char *s = luaL_tolstring(L, i, NULL);

      if (i > 1)
        {
          fputc(' ', stdout);
        }

      fputs(s, stdout);
      lua_pop(L, 1);
    }

  fputc('\n', stdout);
  return 0;
}

/****************************************************************************
 * vapor.write(...) -- like vapor.print, but no separators and no
 * trailing newline. For building output a piece at a time (prompts,
 * progress indicators, anything print's formatting doesn't fit).
 ****************************************************************************/

static int vapor_write(lua_State *L)
{
  int argc = lua_gettop(L);
  int i;

  for (i = 1; i <= argc; i++)
    {
      const char *s = luaL_tolstring(L, i, NULL);
      fputs(s, stdout);
      lua_pop(L, 1);
    }

  return 0;
}

/****************************************************************************
 * vapor.read() -- read one line from stdin, trailing newline stripped.
 * Returns nil on EOF/error.
 ****************************************************************************/

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

/****************************************************************************
 * vapor.sleep(seconds) -- pause for (fractional) seconds. Takes a
 * number, not an integer-only count, so short delays (0.1, 0.05, ...)
 * work for things like animation frame pacing later.
 ****************************************************************************/

static int vapor_sleep(lua_State *L)
{
  lua_Number seconds = luaL_checknumber(L, 1);

  if (seconds > 0)
    {
      useconds_t usec = (useconds_t)(seconds * 1000000);
      usleep(usec);
    }

  return 0;
}

/****************************************************************************
 * vapor.time() -- seconds (with fractional precision) on a monotonic
 * clock. Not wall-clock time -- for measuring elapsed time (timeouts,
 * simple benchmarking, frame timing), not for telling you what time
 * it is.
 ****************************************************************************/

static int vapor_time(lua_State *L)
{
  struct timespec ts;

  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    {
      lua_pushnil(L);
      return 1;
    }

  lua_pushnumber(L, (lua_Number)ts.tv_sec + (lua_Number)ts.tv_nsec / 1e9);
  return 1;
}

void vapor_core_register(lua_State *L)
{
  lua_getglobal(L, "vapor");

  lua_pushcfunction(L, vapor_print);
  lua_setfield(L, -2, "print");

  lua_pushcfunction(L, vapor_write);
  lua_setfield(L, -2, "write");

  lua_pushcfunction(L, vapor_read);
  lua_setfield(L, -2, "read");

  lua_pushcfunction(L, vapor_sleep);
  lua_setfield(L, -2, "sleep");

  lua_pushcfunction(L, vapor_time);
  lua_setfield(L, -2, "time");

  lua_pop(L, 1);
}
